# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends SceneTree
## Headless check of the D3 scene through the native training host, without Python.
##
##   godot --headless --path Godot/demo/d3 -s res://tests/d3_smoke.gd

const MAIN_SCENE := preload("res://demo/main.tscn")
const ENVIRONMENT_PATH := NodePath("ScholaEnvironment")
const POLICY_PATH := "res://policies/q_policy.onnx"
const AUTORESET_DISABLED := 2
const UP := 0
const DOWN := 1
const RIGHT := 3

var _failures := 0
var _host: ScholaTrainingHost
var _agent_id := ""


func _initialize() -> void:
	# The root window enters the tree after _initialize(), so start once the main loop runs.
	_start.call_deferred()


func _start() -> void:
	var scene := _instantiate()
	_run(scene)
	_ok(_host.close(), "close")
	scene.free()
	_run_custom_map()
	quit(1 if _failures > 0 else 0)


## The main scene without its runner and HUD, using the scene's own map unless one is given.
func _instantiate(map := {}) -> Node:
	var scene := MAIN_SCENE.instantiate()
	# The demo's own runner opens a host session, and an environment joins only one session.
	for node_name in ["Runner", "HUD"]:
		scene.get_node(node_name).free()
	(scene.get_node(ENVIRONMENT_PATH) as GridEnvironment).use_saved_map = false
	root.add_child(scene)
	current_scene = scene
	if not map.is_empty():
		var environment := scene.get_node(ENVIRONMENT_PATH) as GridEnvironment
		environment.arena.apply_map(map)
		environment._update_observation_space()
	return scene


func _run_custom_map() -> void:
	_expect(GridArena.validate_map({"size": [2, 6], "goal": [0, 0], "hazards": []}) != "", "a 2-wide map is rejected")
	_expect(GridArena.validate_map({"size": [4, 4], "goal": [1, 1], "hazards": [[1, 1]]}) != "", "a hazard on the goal is rejected")
	_expect(GridArena.validate_map({"size": [4, 4], "goal": [4, 0], "hazards": []}) != "", "a goal outside the grid is rejected")

	var map := {"size": [4, 4], "goal": [3, 0], "hazards": [[1, 3]]}
	_expect(GridArena.validate_map(map) == "", "a 4x4 map is valid")
	var scene := _instantiate(map)
	var environment := scene.get_node(ENVIRONMENT_PATH) as GridEnvironment
	var agent: ScholaAgent = environment.get_agents()[0]
	_expect(agent.observation_space.high == PackedFloat32Array([3, 3, 3, 3]), "observation bounds follow the 4x4 map: %s" % agent.observation_space.high)
	_expect(environment.get_map_summary().begins_with("4×4 · 1 hazard"), "map summary: %s" % environment.get_map_summary())

	_host = ScholaTrainingHost.new()
	scene.add_child(_host)
	if not _ok(_host.initialize_session(), "custom map initialize_session") or not _ok(_host.set_autoreset_mode(AUTORESET_DISABLED), "custom map autoreset"):
		return
	var defined := _host.define()
	if not _ok(defined, "custom map define"):
		return
	_expect(defined.value.environments[0].agents[_agent_id].observation_space.high == [3.0, 3.0, 3.0, 3.0], "the host definition carries the 4x4 bounds")
	environment.random_start = false
	environment.start_cell = Vector2i(0, 3)
	var start: Variant = _reset(null)
	_expect(start == PackedFloat32Array([0, 3, 3, -3]), "custom map start observation %s" % start)
	var last := _step(RIGHT)
	_expect(last.get("terminated") == true and last.info.outcome == "failure", "the custom hazard at (1, 3) ends the episode")
	_ok(_host.close(), "custom map close")
	scene.free()


func _run(scene: Node) -> void:
	var environment := scene.get_node(ENVIRONMENT_PATH) as GridEnvironment
	_expect(environment != null, "the scene has a GridEnvironment")
	if environment == null:
		return
	_expect(environment.get_configuration_errors().is_empty(), "configuration is valid: %s" % ", ".join(environment.get_configuration_errors()))
	var agents := environment.get_agents()
	_expect(agents.size() == 1 and agents[0].agent_id == "agent_0", "one agent with ID agent_0")
	_expect(environment.max_episode_steps == 40, "40-step limit")

	_host = ScholaTrainingHost.new()
	scene.add_child(_host)
	if not _ok(_host.initialize_session(), "initialize_session") or not _ok(_host.set_autoreset_mode(AUTORESET_DISABLED), "set_autoreset_mode"):
		return
	var defined := _host.define()
	if not _ok(defined, "define"):
		return
	var agent_definitions: Dictionary = defined.value.environments[0].agents
	_agent_id = agent_definitions.keys()[0]
	_expect(agent_definitions[_agent_id].observation_space.type == "Box", "Box observation space in the definition")
	_expect(agent_definitions[_agent_id].action_space.type == "Discrete", "Discrete action space in the definition")

	var first: Variant = _reset(123)
	var second: Variant = _reset(123)
	_expect(first == second, "the same seed gives the same start (%s, %s)" % [first, second])

	environment.random_start = false
	var start: Variant = _reset(null)
	_expect(start == PackedFloat32Array([0, 5, 5, -5]), "fixed start observation %s" % start)
	var last := {}
	for action in [RIGHT, RIGHT, RIGHT, RIGHT, RIGHT, UP, UP, UP, UP, UP]:
		last = _step(action)
	_expect(last.get("terminated") == true and last.info.outcome == "success", "reaching the goal terminates with success")
	_expect(is_equal_approx(last.get("reward", 0.0), 9.9), "goal reward is 9.9, got %s" % last.get("reward"))

	_reset(null)
	_step(UP)
	last = _step(RIGHT)
	_expect(last.get("terminated") == true and last.info.outcome == "failure", "a hazard terminates with failure")
	_expect(is_equal_approx(last.get("reward", 0.0), -10.1), "hazard reward is -10.1, got %s" % last.get("reward"))

	_reset(null)
	for i in 39:
		last = _step(DOWN)
	_expect(last.get("truncated") == false, "not truncated before step 40")
	last = _step(DOWN)
	_expect(last.get("truncated") == true and last.get("terminated") == false and last.info.outcome == "timeout", "step 40 truncates with timeout")

	_check_policy(environment, agents[0])


func _check_policy(environment: GridEnvironment, agent: ScholaAgent) -> void:
	if not FileAccess.file_exists(POLICY_PATH):
		print("SKIP ONNX policy: %s not found; run python/create_reference_policy.py and python/export_onnx.py" % POLICY_PATH)
		return
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = POLICY_PATH
	if policy.initialize(agent) != OK:
		_expect(false, "ONNX policy initializes: %s" % policy.get_last_error())
		return
	var state := policy.create_state()
	environment.random_start = false
	var observation: Variant = _reset(null)
	var result := {}
	for i in environment.max_episode_steps:
		var action: Variant = policy.infer(observation, state)
		_expect(typeof(action) == TYPE_INT and action >= 0 and action < 4, "ONNX action %s is in Discrete(4)" % action)
		if typeof(action) != TYPE_INT:
			return
		result = _step(action)
		observation = result.observation
		if result.terminated or result.truncated:
			break
	print("ONNX policy episode from (0, 5) ended with %s" % result.get("info", {}).get("outcome"))


func _reset(seed: Variant) -> Variant:
	var settings := {} if seed == null else {"seed": seed}
	var result := _host.reset({0: settings})
	if not _ok(result, "reset"):
		return null
	return result.value[0][_agent_id].observation


func _step(action: int) -> Dictionary:
	var result := _host.step({"actions": [{_agent_id: action}]})
	if not _ok(result, "step"):
		return {}
	return result.value.state[0][_agent_id]


func _ok(result: Dictionary, what: String) -> bool:
	var ok: bool = result.status.code == 0
	_expect(ok, "%s: %s" % [what, result.status.message])
	return ok


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("D3 smoke check failed: " + message)
