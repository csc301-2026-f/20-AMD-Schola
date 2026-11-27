# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const SCENE := "res://examples/race_track/scenes/race_track_inference.tscn"
const TRAINED_MODEL := "res://examples/race_track/policies/race_track.onnx"
const SWITCHER_MODELS: Array[String] = [
	"res://examples/race_track/policies/race_track_untrained.onnx",
	"res://examples/race_track/policies/race_track_350k_steps.onnx",
	"res://examples/race_track/policies/race_track_650k_steps.onnx",
	TRAINED_MODEL,
]
const EXPORTED_MODEL := "res://tests/inference/fixtures/schola_ppo_race_car.onnx"


func test_inference_scene_drives_the_car_with_a_schola_exported_policy() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var stepper: ScholaInferenceStepper = scene.get_node("InferenceStepper")
	assert_str(stepper.policy.model_path).is_equal(TRAINED_MODEL)

	_use_exported_model(scene)
	var policy: ScholaOnnxPolicy = stepper.policy
	var failures := _collect_failures([stepper])
	add_child(scene)

	await _wait_physics_frames(60)
	var car: VehicleBody3D = scene.get_node("Car")
	var agent: ScholaAgent = scene.get_node("Car/Agent")
	assert_array(failures).is_empty()
	assert_bool(policy.is_initialized()).is_true()
	assert_array(Array(stepper.get_configuration_errors())).is_empty()
	assert_array(Array(agent.get_configuration_errors())).is_empty()

	for component in ["Track", "Velocity", "Rays", "RoadAhead", "Controls"]:
		assert_array(Array(agent.get_node(component).get_configuration_errors())).is_empty()

	assert_float(absf(car.engine_force) + absf(car.steering)).is_greater(0.0)


func test_inference_scene_shows_the_actions_the_policy_chose() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	add_child(scene)

	await _wait_physics_frames(60)
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
	await _wait_physics_frames(10)
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


func test_plus_adds_a_driving_car_ahead_and_minus_removes_the_last_added() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var steppers := _use_exported_model(scene)
	var failures := _collect_failures(steppers)
	add_child(scene)
	var spawner: Node = scene.get_node("CarSpawner")
	var agent: RaceTrackAgent = scene.get_node("Car/Agent")
	var track := agent.track
	await get_tree().physics_frame

	await _press_and_step(KEY_EQUAL)
	await _press_and_step(KEY_KP_ADD)
	assert_int(spawner.added.size()).is_equal(2)
	var first: RaceTrackAgent = spawner.added[0]
	var second: RaceTrackAgent = spawner.added[1]
	var here := track.progress_of(agent.car.global_position)
	var first_at := track.progress_of(first.car.global_position)
	assert_float(first_at - here).is_between(45.0, 60.0)
	assert_float(track.progress_of(second.car.global_position) - first_at).is_greater_equal(35.0)
	assert_object(get_viewport().get_camera_3d()).is_same(scene.get_node("Car/Camera"))

	await _wait_physics_frames(60)
	assert_array(failures).is_empty()
	for added: RaceTrackAgent in [first, second]:
		assert_float(absf(added.controls.action[0]) + absf(added.controls.action[1])).is_greater(0.0)

	await _press_and_step(KEY_MINUS)
	assert_array(spawner.added).contains_exactly([first])
	assert_bool(is_instance_valid(second)).is_false()
	for press in 2:
		await _press_and_step(KEY_KP_SUBTRACT)
	assert_array(spawner.added).is_empty()
	assert_bool(is_instance_valid(first)).is_false()
	assert_bool(is_instance_valid(agent)).is_true()
	assert_array(failures).is_empty()


func test_an_added_car_avoids_obstacles_and_r_lines_the_cars_up() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	add_child(scene)
	var spawner: Node = scene.get_node("CarSpawner")
	var agent: RaceTrackAgent = scene.get_node("Car/Agent")
	var track := agent.track
	await get_tree().physics_frame
	var here := track.progress_of(agent.car.global_position)
	var body := track.add_obstacle(here + 70.0, 0.0)
	spawner.add()
	var added: RaceTrackAgent = spawner.added[0]
	assert_float(track.progress_of(added.car.global_position) - here).is_between(80.0, 90.0)

	body.free()
	agent.car.global_position = track.center_at(400.0)
	added.car.global_position = track.center_at(450.0)
	await _press_and_step(KEY_R)
	assert_float(track.progress_of(agent.car.global_position)).is_between(3.0, 6.0)
	assert_float(track.progress_of(added.car.global_position)).is_between(53.0, 56.0)


func test_h_hides_and_shows_the_rays_of_every_car() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	var failures := _collect_failures([scene.get_node("InferenceStepper")])
	add_child(scene)
	var agent: RaceTrackAgent = scene.get_node("Car/Agent")
	var spawner: Node = scene.get_node("CarSpawner")
	await get_tree().physics_frame
	spawner.add()
	await _wait_physics_frames(3)
	assert_bool(_shows_rays(agent)).is_true()

	await _press_and_step(KEY_H)
	spawner.add()
	await _wait_physics_frames(3)
	for shown: RaceTrackAgent in [agent, spawner.added[0], spawner.added[1]]:
		assert_bool(_shows_rays(shown)).is_false()

	await _press_and_step(KEY_H)
	for shown: RaceTrackAgent in [agent, spawner.added[0], spawner.added[1]]:
		assert_bool(_shows_rays(shown)).is_true()
	assert_array(failures).is_empty()


func test_m_hands_the_car_to_the_keyboard_and_back_to_the_ai() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var steppers := _use_exported_model(scene)
	var failures := _collect_failures(steppers)
	add_child(scene)
	var agent: RaceTrackAgent = scene.get_node("Car/Agent")
	var driver: Label = scene.get_node("ManualDriver")
	var switcher: Label = scene.get_node("ModelSwitcher")
	var spawner: Node = scene.get_node("CarSpawner")
	await _wait_physics_frames(3)
	assert_bool(driver.visible).is_false()

	await _press_and_step(KEY_M)
	assert_bool(driver.visible).is_true()
	assert_array(Array(agent.controls.action)).contains_exactly([0.0, 0.0])
	for step: Array in [[KEY_W, [0.0, 1.0]], [KEY_S, [0.0, -1.0]], [KEY_A, [-1.0, 0.0]], [KEY_D, [1.0, 0.0]]]:
		_hold(step[0], true)
		await _wait_physics_frames(3)
		assert_array(Array(agent.controls.action)).contains_exactly(step[1])
		_hold(step[0], false)
		await _wait_physics_frames(3)

	_hold(KEY_S, true)
	await _wait_physics_frames(120)
	assert_float(agent.car.linear_velocity.dot(agent.car.global_basis.z)).is_between(-6.0, -2.0)
	_hold(KEY_S, false)
	await get_tree().physics_frame

	await _press_and_step(KEY_EQUAL)
	var added: RaceTrackAgent = spawner.added[0]
	await _press_and_step(KEY_2)
	assert_str(switcher.text).contains(switcher.names[1])
	assert_bool(steppers[1].enabled).is_true()
	for stepper in steppers:
		assert_int(stepper.remove_agent(agent)).is_equal(0)
	assert_float(absf(added.controls.action[0]) + absf(added.controls.action[1])).is_greater(0.0)
	assert_array(Array(agent.controls.action)).contains_exactly([0.0, 0.0])

	await _press_and_step(KEY_M)
	assert_bool(driver.visible).is_false()
	assert_float(absf(agent.controls.action[0]) + absf(agent.controls.action[1])).is_greater(0.0)
	assert_array(failures).is_empty()


func test_clicking_drops_an_obstacle_ahead_in_that_lane() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	_use_exported_model(scene)
	add_child(scene)
	var dropper: Node = scene.get_node("ObstacleDropper")
	var car: VehicleBody3D = scene.get_node("Car")
	var track: RaceTrackPath = scene.get_node("Car/Agent").track
	await get_tree().physics_frame

	_click(MOUSE_BUTTON_LEFT, Vector2(get_viewport().get_visible_rect().size.x * 0.1, 100.0))
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

	_click(MOUSE_BUTTON_RIGHT, get_viewport().get_camera_3d().unproject_position(first.global_position))
	await _wait_physics_frames(3)
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

	dropper.remove(obstacle)
	assert_int(obstacle.collision_layer).is_equal(0)
	assert_int(obstacle.collision_mask).is_equal(0)
	assert_bool(obstacle.visible).is_false()

	await _press(KEY_R)
	assert_int(obstacle.collision_layer).is_equal(1)
	assert_int(obstacle.collision_mask).is_equal(1)
	assert_bool(obstacle.visible).is_true()


func test_a_hidden_obstacle_does_not_block_the_car() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var steppers := _use_exported_model(scene)
	add_child(scene)
	for stepper in steppers:
		stepper.enabled = false
	var agent: RaceTrackAgent = scene.get_node("Car/Agent")
	var car := agent.car
	car.contact_monitor = true
	car.max_contacts_reported = 4
	var track := agent.track
	track.set_obstacles(PackedVector2Array([Vector2(120.0, 0.0)]))
	track.set_obstacles(PackedVector2Array())
	get_tree().physics_frame.connect(agent.place.bind(track.transform_at(100.0)), CONNECT_ONE_SHOT)
	var touched := false
	for frame in 180:
		agent.controls._act(PackedFloat32Array([0.0, 1.0]))
		await get_tree().physics_frame
		touched = touched or car.get_colliding_bodies().any(func(body: Node) -> bool: return body.is_in_group("obstacle"))
	assert_bool(touched).is_false()
	assert_float(track.progress_of(car.global_position)).is_greater(125.0)


func test_brake_lights_turn_on_only_while_braking() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var steppers := _use_exported_model(scene)
	add_child(scene)
	for stepper in steppers:
		stepper.enabled = false
	var car: VehicleBody3D = scene.get_node("Car")
	var controls: RaceTrackControls = scene.get_node("Car/Agent/Controls")
	var lights: Node = car.get_node("BrakeLights")
	await get_tree().process_frame
	assert_bool(lights.lit).is_false()
	assert_bool(lights.get_node("Glow").visible).is_false()

	for frame in 20:
		controls._act(PackedFloat32Array([0.0, -1.0]))
		await get_tree().physics_frame
	await get_tree().process_frame
	assert_bool(lights.lit).is_true()
	assert_bool(lights.get_node("Glow").visible).is_true()

	for frame in 60:
		controls._act(PackedFloat32Array([0.0, 0.5]))
		await get_tree().physics_frame
	await get_tree().process_frame
	assert_bool(lights.lit).is_false()


func test_road_ahead_sensor_reports_the_nearest_obstacle_in_each_lane() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var steppers := _use_exported_model(scene)
	add_child(scene)
	for stepper in steppers:
		stepper.enabled = false
	await get_tree().physics_frame
	var agent: RaceTrackAgent = scene.get_node("Car/Agent")
	var sensor: RaceTrackRoadAheadSensor = agent.get_node("RoadAhead")
	var track := agent.track
	var here := track.progress_of(agent.car.global_position)
	track.set_obstacles(PackedVector2Array([Vector2(here + 30.0, 2.5), Vector2(here + 45.0, 0.0), Vector2(here + 90.0, -2.5)]))
	var values: PackedFloat32Array = sensor._observe()
	assert_float(values[0]).is_equal_approx(0.5, 0.02)
	assert_float(values[1]).is_equal_approx(0.75, 0.02)
	assert_float(values[2]).is_equal(1.0)

	var dropper: Node = scene.get_node("ObstacleDropper")
	for child in track.get_children():
		if child.is_in_group("obstacle") and child.visible and child.global_position.distance_to(track.center_at(here + 30.0)) < 4.0:
			dropper.remove(child)
	values = sensor._observe()
	assert_float(values[0]).is_equal(1.0)


func _shows_rays(agent: RaceTrackAgent) -> bool:
	return agent.rays.get_children(true).any(func(child: Node) -> bool: return child is MeshInstance3D and child.visible)


func _wait_physics_frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame


func _collect_failures(steppers: Array) -> Array[String]:
	var failures: Array[String] = []
	for stepper: ScholaInferenceStepper in steppers:
		stepper.inference_failed.connect(func(message: String) -> void: failures.append(message))
	return failures


func _hold(keycode: Key, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = pressed
	Input.parse_input_event(key)


func _click(button: MouseButton, at: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = true
	click.position = at
	Input.parse_input_event(click)


func _press_and_step(keycode: Key) -> void:
	await _press(keycode)
	await _wait_physics_frames(3)


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
