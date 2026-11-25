# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const SCENE := "res://examples/race_track/scenes/race_track_multi_agent_train.tscn"
const PRETRAINED_SCENE := "res://examples/race_track/scenes/race_track_multi_agent_pretrained.tscn"
const CONTROLS := "00000000:Controls"


func before(
	_do_skip := not ClassDB.class_exists("ScholaTrainingConnector"),
	_skip_reason := "Build the training extension (needs gRPC) to run this suite."
) -> void:
	pass


func test_three_cars_train_as_separate_agents_of_one_type() -> void:
	var scene := _scene()
	add_child(scene)
	await get_tree().physics_frame
	var environment: RaceTrackMultiAgentEnvironment = scene.get_node("RaceTrackEnvironment")
	assert_array(Array(environment.get_configuration_errors())).is_empty()
	var agents := environment.get_agents()
	assert_array(agents.map(func(agent: ScholaAgent) -> String: return agent.get_resolved_agent_id())).contains_exactly(["car_1", "car_2", "car_3"])
	for agent: ScholaAgent in agents:
		assert_str(agent.get_resolved_agent_type()).is_equal("race_car")
		assert_array(Array(agent.get_configuration_errors())).is_empty()


func test_pretrained_scene_starts_the_same_cars_from_the_committed_policy() -> void:
	var scene: Node = auto_free(load(PRETRAINED_SCENE).instantiate())
	assert_array(scene.get_node("RaceTrackEnvironment").get_children().map(func(car: Node) -> String: return car.name)).contains_exactly(["Car", "Car2", "Car3"])
	var arguments: PackedStringArray = scene.get_node("EditorTrainer")._arguments()
	assert_bool(arguments.has("--pretrained")).is_true()
	assert_bool(FileAccess.file_exists(arguments[3])).is_true()
	var scratch: Node = auto_free(load(SCENE).instantiate())
	assert_bool(scratch.get_node("EditorTrainer")._arguments().has("--pretrained")).is_false()


func test_each_car_gets_its_own_action_and_reward_and_a_crashed_car_leaves_the_track() -> void:
	var scene := _scene()
	var environment: RaceTrackMultiAgentEnvironment = scene.get_node("RaceTrackEnvironment")
	environment.random_obstacles = false
	environment.random_start = false
	get_tree().root.add_child(scene)
	var previous := get_tree().current_scene
	get_tree().current_scene = scene
	var host := ScholaTrainingHost.new()
	scene.add_child(host)
	await get_tree().physics_frame
	assert_int(host.initialize_session().status.code).is_equal(0)
	assert_int(host.set_autoreset_mode(2).status.code).is_equal(0)
	assert_int(host.define().status.code).is_equal(0)
	assert_int(host.reset({}).status.code).is_equal(0)
	var agents := environment.get_agents()
	var track: RaceTrackPath = agents[0].track
	var length := track.curve.get_baked_length()
	for index in 2:
		var gap := track.progress_of(agents[index + 1].car.global_position) - track.progress_of(agents[index].car.global_position)
		assert_float(fposmod(gap, length)).is_equal_approx(environment.start_spacing, 1.0)

	var state: Dictionary
	for frame in 60:
		await get_tree().physics_frame
		state = _step(host, {"car_1": 1.0, "car_2": 0.0, "car_3": 1.0})
	assert_float(state.car_1.reward).is_greater(state.car_2.reward + 0.02)
	assert_float(state.car_3.reward).is_greater(state.car_2.reward + 0.02)
	assert_str(state.car_2.info.agent).is_equal("car_2")

	agents[0].car.global_position = track.center_at(track.progress_of(agents[0].car.global_position)) + Vector3(0.0, 20.0, 0.0)
	await get_tree().physics_frame
	state = _step(host, {"car_1": 1.0, "car_2": 1.0, "car_3": 1.0})
	assert_bool(state.car_1.terminated).is_true()
	assert_bool(state.car_2.terminated).is_false()
	for frame in 3:
		await get_tree().physics_frame
	assert_bool(agents[0].car.visible).is_false()
	assert_int(agents[0].car.collision_layer).is_equal(0)
	assert_object(get_viewport().get_camera_3d()).is_same(agents[1].car.get_node("Camera"))
	state = _step(host, {"car_2": 1.0, "car_3": 1.0})
	assert_bool(state.car_3.terminated).is_false()

	assert_int(host.reset({}).status.code).is_equal(0)
	await get_tree().physics_frame
	assert_bool(agents[0].car.visible).is_true()
	assert_int(agents[0].car.collision_layer).is_equal(1)
	assert_int(_step_code(host, {"car_1": 1.0, "car_2": 1.0, "car_3": 1.0})).is_equal(0)
	get_tree().current_scene = previous


func _scene() -> Node:
	var scene: Node = auto_free(load(SCENE).instantiate())
	for child in ["TrainingConnector", "EditorTrainer"]:
		var node := scene.get_node(child)
		scene.remove_child(node)
		node.free()
	return scene


func _actions(pedals: Dictionary) -> Dictionary:
	var actions := {}
	for id in pedals:
		actions[id] = {CONTROLS: PackedFloat32Array([0.0, pedals[id]])}
	return {"actions": [actions]}


func _step(host: ScholaTrainingHost, pedals: Dictionary) -> Dictionary:
	var result := host.step(_actions(pedals))
	assert_int(result.status.code).override_failure_message(str(result.status.message)).is_equal(0)
	return result.value.state[0] if result.status.code == 0 else {}


func _step_code(host: ScholaTrainingHost, pedals: Dictionary) -> int:
	return host.step(_actions(pedals)).status.code
