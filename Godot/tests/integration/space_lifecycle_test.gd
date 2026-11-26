# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const ConfiguredAgent := preload("res://tests/integration/support/us15_configured_agent.gd")
const BOX_MODEL := "res://tests/inference/fixtures/box_scale.onnx"


class TestEnvironment extends ScholaEnvironment:
	func _get_step_result(_agent: ScholaAgent) -> Dictionary:
		return {"reward": 1.0, "terminated": false, "truncated": false}


class PossibleEnvironment extends TestEnvironment:
	var possible: Array[ScholaAgent] = []
	func _get_possible_agents() -> Array[ScholaAgent]:
		return possible


class BoxAgent extends ScholaAgent:
	var definition_calls := 0
	var width := 3
	func _define_observation_space() -> ScholaSpace:
		definition_calls += 1
		return ScholaSpaces.box([width], -10, 10)

	func _define_action_space() -> ScholaSpace:
		return ScholaSpaces.box([width], -10, 10)

	func _observe() -> Variant:
		return PackedFloat32Array([1, 2, 3])

	func _act(_action: Variant) -> void:
		pass


class BrokenCallbackAgent extends ScholaAgent:
	func _define_observation_space() -> ScholaSpace:
		var missing := {}
		return missing["spaces"]


class InspectorAgent extends ScholaAgent:
	var last_action: Variant

	func _observe() -> Variant:
		return 0

	func _act(action: Variant) -> void:
		last_action = action


var _driver: RefCounted
var _previous_scene: Node
var _temporary_paths: Array[String] = []


func before_test() -> void:
	_previous_scene = get_tree().current_scene
	assert_bool(ClassDB.class_exists("ScholaEnvironmentTestDriver"))\
		.override_failure_message("Build with integration_tests=yes for space lifecycle coverage.")\
		.is_true()
	if ClassDB.class_exists("ScholaEnvironmentTestDriver"):
		_driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")


func after_test() -> void:
	get_tree().current_scene = _previous_scene
	_driver = null
	for path in _temporary_paths:
		DirAccess.remove_absolute(path)
	_temporary_paths.clear()


func _agent() -> ScholaAgent:
	var agent: ScholaAgent = auto_free(ConfiguredAgent.new())
	agent.name = "Coder"
	agent.agent_id = "coder"
	return agent


func _define(agent: ScholaAgent) -> Dictionary:
	return _driver.call("define_agent", agent)


func _inspector_agent() -> InspectorAgent:
	var agent: InspectorAgent = auto_free(InspectorAgent.new())
	agent.name = "InspectorAgent"
	agent.agent_id = "inspector"
	agent.observation_space = ScholaSpaces.discrete(3)
	agent.action_space = ScholaSpaces.discrete(3)
	return agent


func _host(agent: ScholaAgent, environment: ScholaEnvironment = null) -> ScholaTrainingHost:
	var root: Node = auto_free(Node.new())
	get_tree().root.add_child(root)
	get_tree().current_scene = root
	if environment == null:
		environment = TestEnvironment.new()
	root.add_child(environment)
	environment.add_child(agent)
	var host := ScholaTrainingHost.new()
	root.add_child(host)
	return host


func _start(host: ScholaTrainingHost) -> Dictionary:
	assert_int(host.initialize_session().status.code).is_equal(0)
	assert_int(host.set_autoreset_mode(2).status.code).is_equal(0)
	var definition := host.define()
	assert_int(definition.status.code).is_equal(0)
	return definition


# Save a real PackedScene and reload without the resource cache. Runtime adapter
# state must never be serialized, even when the original agent was resolved.
func _round_trip(agent: ScholaAgent, suffix: String) -> ScholaAgent:
	var scene := PackedScene.new()
	assert_int(scene.pack(agent)).is_equal(OK)
	var path := "user://us15_scene_%s.tscn" % suffix
	_temporary_paths.append(path)
	assert_int(ResourceSaver.save(scene, path)).is_equal(OK)
	var loaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert_object(loaded).is_not_null()
	if loaded == null:
		return null
	return auto_free(loaded.instantiate()) as ScholaAgent


func test_inspector_scene_round_trip_preserves_nested_resources_and_definitions() -> void:
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	agent.name = "InspectorAgent"
	var factory: ScholaAgent = _agent()
	factory.nested = true
	var spaces: Dictionary = factory.make_spaces()
	agent.observation_space = spaces.observation
	agent.action_space = spaces.action
	var original := _define(agent)
	var restored := _round_trip(agent, "inspector")
	if restored == null:
		return
	assert_bool(restored.has_code_defined_spaces()).is_false()
	assert_array(restored.get_configuration_errors()).is_empty()
	var definition := _define(restored)
	assert_bool(definition.ok).is_true()
	assert_dict(definition.observation).is_equal(original.observation)
	assert_dict(definition.action).is_equal(original.action)


func test_callback_scene_round_trip_preserves_authored_fields_and_rebuilds_from_configuration() -> void:
	var agent := _agent()
	agent.choice_count = 5
	agent.observation_space = ScholaSpaces.discrete(9)
	agent.action_space = ScholaSpaces.discrete(8)
	assert_int(_define(agent).observation.n).is_equal(5)
	agent.choice_count = 7
	var restored := _round_trip(agent, "callback")
	if restored == null:
		return
	assert_int(restored.definition_calls).is_equal(0)
	assert_int(restored.observation_space.n).is_equal(9)
	assert_int(restored.action_space.n).is_equal(8)
	assert_int(_define(restored).observation.n).is_equal(7)
	assert_int(restored.definition_calls).is_equal(1)
	assert_int(_define(agent).observation.n).is_equal(5)


func test_tree_exit_and_reentry_keep_callback_snapshot_after_configuration_edits() -> void:
	var agent := _agent()
	add_child(agent)
	assert_int(_define(agent).observation.n).is_equal(3)
	remove_child(agent)
	agent.choice_count = 7
	add_child(agent)
	assert_int(_define(agent).observation.n).is_equal(3)
	assert_int(agent.definition_calls).is_equal(1)


func test_tree_exit_and_reentry_keep_inspector_snapshot() -> void:
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	agent.observation_space = ScholaSpaces.discrete(3)
	agent.action_space = ScholaSpaces.discrete(2)
	add_child(agent)
	assert_bool(_define(agent).ok).is_true()
	remove_child(agent)
	agent.observation_space.n = 7
	add_child(agent)
	assert_int(_define(agent).observation.n).is_equal(3)
	assert_int(agent.observation_space.n).is_equal(7)


func test_inspector_mutation_after_session_initialization_does_not_block_host_definition() -> void:
	for clear_action in [false, true]:
		var agent := _inspector_agent()
		var host := _host(agent)
		assert_int(host.initialize_session().status.code).is_equal(0)
		# Initialization captured both spaces. Editor diagnostics must still show
		# the now-invalid authored fields, while runtime keeps that snapshot.
		agent.observation_space.n = 0
		if clear_action:
			agent.action_space = null
		else:
			agent.action_space.n = 0
		assert_array(agent.get_configuration_errors()).is_not_empty()
		assert_array(agent.get_parent().get_configuration_errors()).is_not_empty()
		assert_array(_driver.call("get_agent_warnings", agent)).is_not_empty()
		assert_int(host.set_autoreset_mode(2).status.code).is_equal(0)
		var definition := host.define()
		assert_int(definition.status.code).override_failure_message(definition.status.message).is_equal(0)
		if definition.status.code != 0:
			continue
		var declared: Dictionary = definition.value.environments[0].agents.inspector
		assert_int(declared.observation_space.n).is_equal(3)
		assert_int(declared.action_space.n).is_equal(3)
		assert_int(host.reset({}).status.code).is_equal(0)
		assert_int(host.step({"actions": [{"inspector": 2}]}).status.code).is_equal(0)
		assert_int(agent.last_action).is_equal(2)
		assert_int(host.step({"actions": [{"inspector": 3}]}).status.code).is_not_equal(0)
		assert_int(agent.last_action).is_equal(2)


func test_inspector_snapshot_from_another_consumer_is_used_at_training_start() -> void:
	var agent := _inspector_agent()
	assert_bool(_define(agent).ok).is_true()
	agent.observation_space.n = 0
	agent.action_space = null
	var host := _host(agent)
	var initialized := host.initialize_session()
	assert_int(initialized.status.code).override_failure_message(initialized.status.message).is_equal(0)


func test_direct_environment_initialization_uses_existing_inspector_snapshot() -> void:
	var agent := _inspector_agent()
	_host(agent)
	assert_bool(_define(agent).ok).is_true()
	agent.observation_space.n = 0
	agent.action_space = null
	var environment := agent.get_parent() as ScholaEnvironment
	var initialized: Dictionary = _driver.call("initialize", environment)
	assert_bool(initialized.ok).override_failure_message(initialized.message).is_true()
	if not initialized.ok:
		return
	assert_bool(_driver.call("reset", environment).ok).is_true()
	assert_bool(_driver.call("step", environment, {"inspector": 2}).ok).is_true()
	assert_int(agent.last_action).is_equal(2)
	assert_array(agent.get_configuration_errors()).is_not_empty()
	assert_bool(_driver.call("step", environment, {"inspector": 3}).ok).is_false()


func test_invalid_inspector_spaces_still_fail_before_first_resolution() -> void:
	var agent := _inspector_agent()
	agent.observation_space.n = 0
	var host := _host(agent)
	var initialized := host.initialize_session()
	assert_int(initialized.status.code).is_not_equal(0)
	assert_str(initialized.status.message).contains("inspector")
	assert_str(initialized.status.message).contains("observation_space")


func test_nested_values_and_snapshots_survive_repeated_episode_resets() -> void:
	var agent := _agent()
	agent.nested = true
	var spaces: Dictionary = agent.make_spaces()
	agent.observation = spaces.observation.make_default_value()
	var action: Dictionary = spaces.action.make_default_value()
	var host := _host(agent)
	_start(host)
	# Mutate a deeply nested shared resource after the core snapshot exists.
	agent.last_spaces.action.spaces.controls.spaces.mode.n = 1
	agent.choice_count = 1
	action.controls.mode = 2
	for episode in range(3):
		assert_int(host.reset({}).status.code).is_equal(0)
		var stepped := host.step({"actions": [{"coder": action}]})
		assert_int(stepped.status.code).override_failure_message(stepped.status.message).is_equal(0)
		assert_dict(agent.last_action).is_equal(action)
	assert_int(agent.definition_calls).is_equal(1)


func test_nested_action_failure_names_path_and_never_runs_act() -> void:
	var agent := _agent()
	agent.nested = true
	var spaces: Dictionary = agent.make_spaces()
	agent.observation = spaces.observation.make_default_value()
	var action: Dictionary = spaces.action.make_default_value()
	action.controls.mode = 99
	var host := _host(agent)
	_start(host)
	assert_int(host.reset({}).status.code).is_equal(0)
	var failed := host.step({"actions": [{"coder": action}]})
	assert_int(failed.status.code).is_not_equal(0)
	assert_str(failed.status.message).contains("controls.mode")
	assert_object(agent.last_action).is_null()


func test_nested_observation_failure_names_path() -> void:
	var agent := _agent()
	agent.nested = true
	var spaces: Dictionary = agent.make_spaces()
	agent.observation = spaces.observation.make_default_value()
	agent.observation.joints.joint_1.contact = PackedByteArray([2, 0])
	var host := _host(agent)
	_start(host)
	var failed := host.reset({})
	assert_int(failed.status.code).is_not_equal(0)
	assert_str(failed.status.message).contains("joints.joint_1.contact")


func test_later_environment_failure_keeps_successful_agent_snapshot_on_retry() -> void:
	var agent := _agent()
	var host := _host(agent)
	var broken := ConfiguredAgent.new()
	broken.name = "Broken"
	broken.choice_count = 0
	agent.get_parent().add_child(broken)
	assert_int(host.initialize_session().status.code).is_not_equal(0)
	assert_int(agent.definition_calls).is_equal(1)
	agent.choice_count = 9
	broken.choice_count = 4
	var definition := _start(host)
	assert_int(definition.value.environments[0].agents.coder.observation_space.n).is_equal(3)
	assert_int(agent.definition_calls).is_equal(1)


func test_training_policy_and_stepper_share_one_snapshot_and_policy_reinitialization_keeps_it() -> void:
	var agent: BoxAgent = auto_free(BoxAgent.new())
	var host := _host(agent)
	_start(host)
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = BOX_MODEL
	assert_int(policy.initialize(agent)).is_equal(OK)
	agent.width = 4
	assert_int(policy.initialize(agent)).is_equal(OK)
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.enabled = false
	stepper.policy = policy
	add_child(stepper)
	assert_int(stepper.add_agent(agent)).is_equal(OK)
	assert_int(stepper.step()).is_equal(OK)
	assert_int(agent.definition_calls).is_equal(1)


func test_code_defined_stacker_keeps_adapted_definition_and_history_across_define_calls() -> void:
	var agent := _agent()
	agent.observation = 1
	var stacker := ScholaStacker.new()
	stacker.output_kind = 1
	stacker.stack_size = 3
	stacker.default_point = 0
	agent.observation_adapters = [stacker]
	_host(agent)
	var environment := agent.get_parent() as ScholaEnvironment
	assert_bool(_driver.call("initialize", environment).ok).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()
	agent.observation = 2
	stacker.stack_size = 4
	agent.last_spaces.observation.n = 0
	for index in range(2):
		var definition := _define(agent)
		assert_bool(definition.ok).is_true()
		assert_int(definition.observation.spaces.size()).is_equal(3)
	var stepped: Dictionary = _driver.call("step", environment, {"coder": 1})
	assert_bool(stepped.ok).override_failure_message(stepped.message).is_true()
	assert_dict(stepped.states.coder.observation).is_equal({"Point_0": 2, "Point_1": 1, "Point_2": 0})
	assert_int(agent.definition_calls).is_equal(1)


func test_dynamic_training_resolves_detached_possible_agent_before_live_agent() -> void:
	var prototype := _agent()
	var live := _agent()
	var environment := PossibleEnvironment.new()
	environment.possible = [prototype]
	var host := _host(live, environment)
	assert_int(host.initialize_session().status.code).is_equal(0)
	assert_int(prototype.definition_calls).is_equal(1)
	assert_int(live.definition_calls).is_equal(0)
	assert_int(host.set_autoreset_mode(2).status.code).is_equal(0)
	assert_int(host.define().status.code).is_equal(0)
	assert_int(host.reset({}).status.code).is_equal(0)
	assert_int(live.definition_calls).is_equal(1)
	assert_int(host.step({"actions": [{"coder": 2}]}).status.code).is_equal(0)
	assert_int(prototype.definition_calls).is_equal(1)
	assert_int(live.definition_calls).is_equal(1)


func test_failed_action_definition_does_not_cache_the_valid_observation_half() -> void:
	var agent := _agent()
	agent.nested = true
	agent.joint_count = 0 # Invalid action Box shape; observation remains valid.
	var failed := _define(agent)
	assert_bool(failed.ok).is_false()
	assert_bool(failed.has("observation")).is_false()
	assert_bool(failed.has("action")).is_false()
	agent.joint_count = 4
	var corrected := _define(agent)
	assert_bool(corrected.ok).is_true()
	assert_int(corrected.observation.spaces.joints.spaces.size()).is_equal(4)
	assert_array(corrected.action.spaces.motors.shape).contains_exactly([4])
	assert_int(agent.definition_calls).is_equal(2)
	assert_int(agent.action_definition_calls).is_equal(2)


func test_script_runtime_failure_publishes_no_snapshot_and_allows_corrected_script() -> void:
	var agent: ScholaAgent = auto_free(BrokenCallbackAgent.new())
	agent.name = "BrokenCallback"
	agent.observation_space = ScholaSpaces.discrete(9)
	agent.action_space = ScholaSpaces.discrete(9)
	var results: Array[Dictionary] = []
	await assert_error(func() -> void: results.append(_define(agent))).is_runtime_error(
		"Invalid access to property or key 'spaces' on a base object of type 'Dictionary'."
	)
	assert_int(results.size()).is_equal(1)
	if results.is_empty():
		return
	assert_bool(results[0].ok).is_false()
	assert_str(results[0].message).contains("Agent 'BrokenCallback'")
	assert_str(results[0].message).contains("_define_observation_space()")
	assert_bool(results[0].has("observation")).is_false()
	agent.set_script(ConfiguredAgent)
	assert_int(_define(agent).observation.n).is_equal(3)


func _spaces(observation: ScholaSpace, action: ScholaSpace) -> Dictionary:
	return {"observation": observation, "action": action}
