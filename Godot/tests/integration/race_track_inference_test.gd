# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const SCENE := "res://examples/race_track/scenes/race_track_inference.tscn"
const TRAINED_MODEL := "res://examples/race_track/policies/race_track.onnx"
const SWITCHER_MODELS: Array[String] = [
	"res://examples/race_track/policies/race_track_untrained.onnx",
	"res://examples/race_track/policies/race_track_25k_steps.onnx",
	"res://examples/race_track/policies/race_track_350k_steps.onnx",
	TRAINED_MODEL,
]
const EXPORTED_MODEL := "res://tests/inference/fixtures/schola_ppo_race_car.onnx"


func test_inference_scene_drives_the_car_with_a_schola_exported_policy() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var stepper: ScholaInferenceStepper = scene.get_node("InferenceStepper")
	assert_str(stepper.policy.model_path).is_equal(TRAINED_MODEL)

	_use_exported_model(scene)
	var policy: ScholaOnnxPolicy = stepper.policy
	var failures: Array[String] = []
	stepper.inference_failed.connect(func(message: String) -> void: failures.append(message))
	add_child(scene)

	for frame in 60:
		await get_tree().physics_frame
	var car: VehicleBody3D = scene.get_node("Car")
	var agent: ScholaAgent = scene.get_node("Car/Agent")
	assert_array(failures).is_empty()
	assert_bool(policy.is_initialized()).is_true()
	assert_array(Array(stepper.get_configuration_errors())).is_empty()
	assert_array(Array(agent.get_configuration_errors())).is_empty()

	for component in ["Track", "Velocity", "Controls"]:
		assert_array(Array(agent.get_node(component).get_configuration_errors())).is_empty()

	assert_float(absf(car.engine_force) + absf(car.steering)).is_greater(0.0)


func test_inference_scene_shows_the_actions_the_policy_chose() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	add_child(scene)

	for frame in 60:
		await get_tree().physics_frame
	var controls: RaceTrackControls = scene.get_node("Car/Agent/Controls")
	assert_object(scene.get_node("ActionDisplay").controls).is_same(controls)
	assert_object(scene.get_node("ActionDisplay").car).is_same(scene.get_node("Car"))
	assert_float(absf(controls.action[0]) + absf(controls.action[1])).is_greater(0.0)


func test_model_switcher_changes_model_in_place_and_r_restarts_the_car() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var switcher: Node = scene.get_node("ModelSwitcher")
	var models: Array[String] = []
	for path in switcher.stepper_paths:
		models.append((switcher.get_node(path) as ScholaInferenceStepper).policy.model_path)
	assert_array(models).contains_exactly(SWITCHER_MODELS)

	var steppers := _use_exported_model(scene)
	add_child(scene)
	assert_array(steppers.map(func(stepper: ScholaInferenceStepper) -> bool: return stepper.enabled)).contains_exactly([false, false, false, true])

	assert_str(switcher.text).contains(switcher.names[3])

	var car: VehicleBody3D = scene.get_node("Car")
	var track: RaceTrackPath = scene.get_node("Car/Agent").track
	await get_tree().physics_frame
	car.global_position = track.center_at(320.0)
	car.linear_velocity = Vector3(0.0, 0.0, 5.0)
	for frame in 10:
		await get_tree().physics_frame
	var max_fps := Engine.max_fps
	Engine.max_fps = 20
	await _press(KEY_1)
	assert_array(steppers.map(func(stepper: ScholaInferenceStepper) -> bool: return stepper.enabled)).contains_exactly([true, false, false, false])
	assert_str(switcher.text).contains(switcher.names[0])
	assert_float(car.global_position.distance_to(track.start_transform().origin)).is_greater(100.0)

	await _press(KEY_R)
	Engine.max_fps = max_fps
	assert_str(switcher.text).contains(switcher.names[0])
	assert_float(car.global_position.distance_to(track.start_transform().origin)).is_less(0.5)


func test_clicking_drops_an_obstacle_ahead_in_that_lane() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	add_child(scene)
	var dropper: Node = scene.get_node("ObstacleDropper")
	var car: VehicleBody3D = scene.get_node("Car")
	var track: RaceTrackPath = scene.get_node("Car/Agent").track
	await get_tree().physics_frame

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(get_viewport().get_visible_rect().size.x * 0.1, 100.0)
	Input.parse_input_event(click)
	for frame in 3:
		await get_tree().process_frame
	assert_int(dropper.dropped.size()).is_equal(1)
	var body: StaticBody3D = dropper.dropped[0].body
	assert_bool(body.is_in_group("obstacle")).is_true()
	await get_tree().create_timer(1.0).timeout

	var offset := track.progress_of(body.global_position)
	assert_float(offset - track.progress_of(car.global_position)).is_between(45.0, 60.0)
	var left := Vector3.UP.cross(track.direction_at(offset)).normalized()
	assert_float((body.global_position - track.center_at(offset)).dot(left)).is_equal_approx(2.5, 0.1)
	assert_float(body.global_position.y - track.center_at(offset).y).is_equal_approx(0.5, 0.05)

	dropper.drop(0.0)
	assert_int(dropper.dropped.size()).is_equal(2)
	assert_float(dropper.dropped[1].offset - dropper.dropped[0].offset).is_greater_equal(25.0)

	await _press(KEY_R)
	assert_array(dropper.dropped).is_empty()


func test_right_click_and_delete_remove_dropped_obstacles() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	add_child(scene)
	var dropper: Node = scene.get_node("ObstacleDropper")
	await get_tree().physics_frame
	dropper.drop(2.5)
	dropper.drop(-2.5)
	dropper.drop(0.0)
	var first: StaticBody3D = dropper.dropped[0].body
	var first_id := first.get_instance_id()
	var last_id: int = dropper.dropped[2].body.get_instance_id()
	await get_tree().create_timer(1.0).timeout

	await _press(KEY_DELETE)
	assert_int(dropper.dropped.size()).is_equal(2)
	assert_bool(dropper.dropped.any(func(item: Dictionary) -> bool: return item.body.get_instance_id() == last_id)).is_false()

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = get_viewport().get_camera_3d().unproject_position(first.global_position)
	Input.parse_input_event(click)
	for frame in 3:
		await get_tree().physics_frame
	assert_int(dropper.dropped.size()).is_equal(1)
	assert_bool(dropper.dropped.any(func(item: Dictionary) -> bool: return item.body.get_instance_id() == first_id)).is_false()


func test_removed_map_obstacle_comes_back_with_r() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	add_child(scene)
	var dropper: Node = scene.get_node("ObstacleDropper")
	var track: RaceTrackPath = scene.get_node("Car/Agent").track
	await get_tree().physics_frame
	var obstacle: StaticBody3D = null
	for child in track.get_children():
		if child.is_in_group("obstacle") and child.global_position.distance_to(track.center_at(325.0)) < 4.0:
			obstacle = child
	var layer := obstacle.collision_layer

	dropper.remove(obstacle)
	assert_int(obstacle.collision_layer).is_equal(0)
	assert_bool(obstacle.visible).is_false()

	await _press(KEY_R)
	assert_int(obstacle.collision_layer).is_equal(layer)
	assert_bool(obstacle.visible).is_true()


func _press(keycode: Key) -> void:
	await get_tree().process_frame
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	Input.parse_input_event(key)
	var release: InputEventKey = key.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	for frame in 3:
		await get_tree().process_frame


func _use_exported_model(scene: Node) -> Array[ScholaInferenceStepper]:
	var steppers: Array[ScholaInferenceStepper] = []
	var switcher: Node = scene.get_node("ModelSwitcher")
	for path in switcher.stepper_paths:
		var stepper: ScholaInferenceStepper = switcher.get_node(path)
		var policy := ScholaOnnxPolicy.new()
		policy.model_path = EXPORTED_MODEL
		stepper.policy = policy
		steppers.append(stepper)
	return steppers
