# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# US13: the RaceTrack training scene is wired the way train.py expects, without
# starting a training session. The connector is removed before the scene enters
# the tree because it blocks on its first physics frame waiting for Python.
#
# Needs the training extension (which needs gRPC), so it is skipped without it.
extends GdUnitTestSuite

const SCENE := "res://examples/race_track/scenes/race_track_train.tscn"
const TRAIN_PY_PORT := 8000


func before(
	_do_skip := not ClassDB.class_exists("ScholaTrainingConnector"),
	_skip_reason := "Build the training extension (needs gRPC) to run this suite."
) -> void:
	pass


func test_training_scene_is_configured_for_train_py() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var connector: Node = scene.get_node("TrainingConnector")
	assert_str(connector.get_class()).is_equal("ScholaTrainingConnector")
	assert_int(connector.port).is_equal(TRAIN_PY_PORT)
	scene.remove_child(connector)
	connector.free()

	add_child(scene)
	await get_tree().physics_frame

	var environment: RaceTrackEnvironment = scene.get_node("RaceTrackEnvironment")
	var agent: ScholaAgent = scene.get_node("RaceTrackEnvironment/Car/Agent")
	assert_array(Array(environment.get_configuration_errors())).is_empty()
	assert_array(Array(agent.get_configuration_errors())).is_empty()
	for component in ["Track", "Velocity", "Rays", "Controls"]:
		assert_array(Array(agent.get_node(component).get_configuration_errors())).is_empty()
	assert_array(environment.get_agents()).contains_exactly([agent])
	assert_int(environment.maximum_steps).is_equal(3000)
	assert_int(environment.maximum_stalled_steps).is_equal(120)
	assert_float(environment.maximum_track_distance).is_equal(4.5)
	assert_bool(environment.random_start).is_true()

	var observation: ScholaDictSpace = agent.get_effective_observation_space()
	assert_array(observation.spaces.keys()).contains_exactly(["00000000:Track", "00000001:Velocity", "00000002:Rays"])
	assert_array(Array(observation.spaces["00000000:Track"].shape)).contains_exactly([6])
	assert_array(Array(observation.spaces["00000001:Velocity"].shape)).contains_exactly([3])
	assert_array(Array(observation.spaces["00000002:Rays"].shape)).contains_exactly([27])

	var action: ScholaDictSpace = agent.get_effective_action_space()
	assert_array(action.spaces.keys()).contains_exactly(["00000000:Controls"])
	var controls: ScholaBoxSpace = action.spaces["00000000:Controls"]
	assert_array(Array(controls.shape)).contains_exactly([2])
	assert_array(Array(controls.low)).contains_exactly([-1.0, -1.0])
	assert_array(Array(controls.high)).contains_exactly([1.0, 1.0])
