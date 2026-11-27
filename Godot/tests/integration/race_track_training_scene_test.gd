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
	_remove_connector(scene)

	add_child(scene)
	await get_tree().physics_frame

	var environment: RaceTrackEnvironment = scene.get_node("RaceTrackEnvironment")
	var agent: ScholaAgent = scene.get_node("RaceTrackEnvironment/Car/Agent")
	assert_array(Array(environment.get_configuration_errors())).is_empty()
	assert_array(Array(agent.get_configuration_errors())).is_empty()
	for component in ["Track", "Velocity", "Rays", "RoadAhead", "Controls"]:
		assert_array(Array(agent.get_node(component).get_configuration_errors())).is_empty()
	assert_array(environment.get_agents()).contains_exactly([agent])
	assert_int(environment.maximum_steps).is_equal(3000)
	assert_int(environment.maximum_stalled_steps).is_equal(120)
	assert_float(environment.maximum_track_distance).is_equal(4.5)
	assert_bool(environment.random_start).is_true()
	assert_bool(environment.random_obstacles).is_true()
	assert_bool(environment.terminate_on_obstacle).is_true()
	assert_bool(environment.car.contact_monitor).is_true()
	assert_int(environment.car.max_contacts_reported).is_greater(0)

	var observation: ScholaDictSpace = agent.get_effective_observation_space()
	assert_array(observation.spaces.keys()).contains_exactly(["00000000:Track", "00000001:Velocity", "00000002:Rays", "00000003:RoadAhead"])
	assert_array(Array(observation.spaces["00000000:Track"].shape)).contains_exactly([6])
	assert_array(Array(observation.spaces["00000001:Velocity"].shape)).contains_exactly([3])
	assert_array(Array(observation.spaces["00000002:Rays"].shape)).contains_exactly([75])
	assert_array(Array(observation.spaces["00000003:RoadAhead"].shape)).contains_exactly([3])

	var action: ScholaDictSpace = agent.get_effective_action_space()
	assert_array(action.spaces.keys()).contains_exactly(["00000000:Controls"])
	var controls: ScholaBoxSpace = action.spaces["00000000:Controls"]
	assert_array(Array(controls.shape)).contains_exactly([2])
	assert_array(Array(controls.low)).contains_exactly([-1.0, -1.0])
	assert_array(Array(controls.high)).contains_exactly([1.0, 1.0])


func test_reward_chart_plots_the_average_reward_per_second() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_remove_connector(scene)
	add_child(scene)
	var environment: RaceTrackEnvironment = scene.get_node("RaceTrackEnvironment")
	var chart: Control = scene.get_node("RewardChart")
	for step in chart.STEPS_PER_POINT - 1:
		environment.step_rewarded.emit(0.1)
	assert_int(chart.points.size()).is_equal(0)
	environment.step_rewarded.emit(0.1)
	assert_int(chart.points.size()).is_equal(1)
	assert_float(chart.points[0]).is_equal_approx(6.0, 0.01)
	for step in chart.STEPS_PER_POINT:
		environment.step_rewarded.emit(0.2)
	assert_float(chart.points[1]).is_equal_approx(6.6, 0.01)


func test_random_obstacle_layouts_vary_and_stay_passable() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_remove_connector(scene)
	add_child(scene)
	await get_tree().physics_frame
	var track: RaceTrackPath = scene.get_node("RaceTrackEnvironment").agent.track
	var length := track.curve.get_baked_length()
	var sizes: Array[int] = []
	for seed in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var layout := track.random_obstacle_layout(rng)
		sizes.append(layout.size())
		var lanes := {}
		for obstacle in layout:
			assert_float(obstacle.x).is_between(track.CLEAR_AFTER_START, length - track.CLEAR_BEFORE_START)
			for jump in track.jumps:
				var ahead := fposmod(jump - obstacle.x, length)
				assert_bool(ahead >= track.CLEAR_BEFORE_JUMP and ahead <= length - track.CLEAR_AFTER_JUMP).is_true()
			lanes[obstacle.x] = lanes.get(obstacle.x, 0) + 1
		for offset in lanes:
			assert_int(lanes[offset]).is_less_equal(2)
			for other in lanes:
				var gap := absf(track.offset_between(offset, other))
				if gap > 0.0 and lanes[offset] == 1:
					assert_float(gap).is_greater_equal(track.GATE_SPACING.x)
	assert_int(sizes.min()).is_less_equal(2)
	assert_int(sizes.max()).is_greater_equal(17)

	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var crowded := track.random_obstacle_layout(rng)
	track.set_obstacles(crowded)
	track.set_obstacles(PackedVector2Array([Vector2(100.0, 0.0)]))
	var shown := track.get_children().filter(func(child: Node) -> bool: return child.is_in_group("obstacle") and child.visible)
	assert_int(shown.size()).is_equal(1)
	assert_int(track.get_children().filter(func(child: Node) -> bool: return child.is_in_group("obstacle") and child.collision_layer != 0).size()).is_equal(1)
	assert_int(track.get_children().filter(func(child: Node) -> bool: return child.is_in_group("obstacle") and child.collision_mask != 0).size()).is_equal(1)


func _remove_connector(scene: Node) -> void:
	var connector := scene.get_node("TrainingConnector")
	scene.remove_child(connector)
	connector.free()
