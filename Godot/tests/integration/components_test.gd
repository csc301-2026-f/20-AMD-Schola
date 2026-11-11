# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

class Sensor extends ScholaSensor:
	var value: Variant = 1
	func _observe() -> Variant:
		return value

class CountingSensor extends Sensor:
	var validations: int = 0
	func _get_component_errors() -> PackedStringArray:
		validations += 1
		return PackedStringArray()

class Actuator extends ScholaActuator:
	var calls: int = 0
	var value: Variant
	func _act(action: Variant) -> void:
		calls += 1
		value = action

class DirectAgent extends ScholaAgent:
	var value: Variant
	func _observe() -> Variant:
		return 2
	func _act(action: Variant) -> void:
		value = action

class ComponentEnvironment extends ScholaEnvironment:
	func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
		pass
	func _get_step_result(_agent: ScholaAgent) -> Variant:
		return {"reward": 0}

var driver: RefCounted
var environment: ComponentEnvironment
var agent: ScholaAgent

func before_test() -> void:
	driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")
	environment = auto_free(ComponentEnvironment.new())
	agent = ScholaAgent.new()
	agent.name = "A"
	environment.add_child(agent)
	add_child(environment)

func after_test() -> void:
	driver = null

func _space() -> ScholaDiscreteSpace:
	var result := ScholaDiscreteSpace.new()
	result.n = 3
	return result

func _sensor(id: String, parent: Node = null) -> Sensor:
	var sensor := Sensor.new()
	sensor.component_id = id
	sensor.space = _space()
	if parent == null:
		parent = agent
	parent.add_child(sensor)
	return sensor

func _actuator(id: String) -> Actuator:
	var actuator := Actuator.new()
	actuator.component_id = id
	actuator.space = _space()
	agent.add_child(actuator)
	return actuator

func test_composition_preserves_tree_order_through_native_adapter() -> void:
	_sensor("z")
	var branch := Node.new()
	agent.add_child(branch)
	_sensor("a", branch)
	var z := _actuator("z")
	var a := _actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var response: Dictionary = driver.call("step", environment, {"A": {"00000000:z": 2, "00000001:a": 1}})
	assert_bool(response.ok).is_true()
	assert_array(response.states.A.observation.keys()).contains_exactly(["00000000:z", "00000001:a"])
	assert_int(z.value).is_equal(2)
	assert_int(a.value).is_equal(1)

func test_invalid_action_has_no_component_side_effects() -> void:
	_sensor("s")
	var first := _actuator("first")
	var second := _actuator("second")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	assert_bool(driver.call("step", environment, {"A": {"00000000:first": 1, "00000001:second": 99}}).ok).is_false()
	assert_int(first.calls).is_equal(0)
	assert_int(second.calls).is_equal(0)

func test_duplicate_identifiers_rejected() -> void:
	_sensor("same")
	_sensor("same")
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_false()

func test_changed_layout_requires_redefinition() -> void:
	_sensor("s")
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	_sensor("new")
	assert_bool(driver.call("step", environment, {"A": {"00000000:a": 1}}).ok).is_false()

func test_ray_sensor_and_movement_actuator_scripts_load() -> void:
	var ray_sensor: ScholaSensor = auto_free(load("res://addons/schola/components/ray_cast_sensor_3d.gd").new())
	var movement: ScholaActuator = auto_free(load("res://addons/schola/components/movement_actuator_3d.gd").new())
	assert_bool(ray_sensor.space is ScholaBoxSpace).is_true()
	assert_str(movement.space.get_definition_error()).is_empty()

func test_movement_applies_local_velocity_and_rejects_missing_body() -> void:
	_sensor("s")
	var movement: ScholaActuator = load("res://addons/schola/components/movement_actuator_3d.gd").new()
	movement.component_id = "move"
	agent.add_child(movement)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	var body := CharacterBody3D.new()
	body.name = "Body"
	body.rotation.y = PI / 2.0
	agent.add_child(body)
	movement.body_path = NodePath("../Body")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	assert_bool(driver.call("step", environment, {"A": {"00000000:move": PackedFloat32Array([1, 0, 0])}}).ok).is_true()
	assert_vector(body.velocity).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.0001)

func test_ray_reports_hit_distance_and_miss() -> void:
	var sensor: ScholaSensor = load("res://addons/schola/components/ray_cast_sensor_3d.gd").new()
	sensor.component_id = "ray"
	agent.add_child(sensor)
	var ray := RayCast3D.new()
	ray.name = "Ray"
	ray.target_position = Vector3(0, 0, -10)
	agent.add_child(ray)
	var paths: Array[NodePath] = [NodePath("../Ray")]
	sensor.rays = paths
	_actuator("a")
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	obstacle.add_child(collision)
	obstacle.position = Vector3(0, 0, -5)
	agent.add_child(obstacle)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var hit: Dictionary = driver.call("step", environment, {"A": {"00000000:a": 0}})
	assert_bool(hit.ok).is_true()
	var values: PackedFloat32Array = hit.states.A.observation["00000000:ray"]
	assert_float(values[0]).is_equal(1.0)
	assert_float(values[1]).is_equal_approx(0.45, 0.001)
	obstacle.position.x = 20
	await get_tree().physics_frame
	await get_tree().physics_frame
	var miss: Dictionary = driver.call("step", environment, {"A": {"00000000:a": 0}})
	assert_bool(miss.ok).is_true()
	assert_array(Array(miss.states.A.observation["00000000:ray"])).contains_exactly([0.0, 0.0])

func test_direct_hooks_take_precedence_over_components() -> void:
	environment.remove_child(agent)
	agent.free()
	var direct := DirectAgent.new()
	agent = direct
	agent.name = "A"
	agent.observation_space = _space()
	agent.action_space = _space()
	environment.add_child(agent)
	_sensor("ignored").space = null
	_actuator("ignored").space = null
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var result: Dictionary = driver.call("step", environment, {"A": 1})
	assert_bool(result.ok).is_true()
	assert_int(result.states.A.observation).is_equal(2)
	assert_int(direct.value).is_equal(1)

func test_nested_agent_is_a_discovery_boundary() -> void:
	_sensor("outer")
	_actuator("outer")
	var nested := ScholaAgent.new()
	agent.add_child(nested)
	_sensor("inner", nested)
	assert_array(agent.observation_space.spaces.keys()).contains_exactly(["00000000:outer"])

func test_configuration_errors_cover_placement_space_and_duplicates() -> void:
	var orphan: ScholaSensor = auto_free(ScholaSensor.new())
	assert_bool(orphan.get_configuration_errors().is_empty()).is_false()
	var first := _sensor("duplicate")
	var second := _sensor("duplicate")
	assert_bool(first.get_configuration_errors().is_empty()).is_false()
	second.component_id = "unique"
	assert_bool(first.get_configuration_errors().is_empty()).is_true()
	first.space = null
	assert_bool(first.get_configuration_errors().is_empty()).is_false()

func test_dispatch_validation_work_scales_with_component_count() -> void:
	var sensors: Array[CountingSensor] = []
	for index in 12:
		var sensor := CountingSensor.new()
		sensor.component_id = "sensor" + str(index)
		sensor.space = _space()
		agent.add_child(sensor)
		sensors.append(sensor)
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	for sensor in sensors:
		sensor.validations = 0
	assert_bool(driver.call("step", environment, {"A": {"00000000:a": 0}}).ok).is_true()
	# Validation must be bounded per component, independent of sibling count.
	for sensor in sensors:
		assert_int(sensor.validations).is_less_equal(8)

func test_unicode_ids_round_trip_through_observation_and_action_dispatch() -> void:
	_sensor("café猫🌍")
	var actuator := _actuator("café猫🌍")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var response: Dictionary = driver.call("step", environment, {"A": {"00000000:café猫🌍": 2}})
	assert_bool(response.ok).is_true()
	assert_dict(response.states.A.observation).is_equal({"00000000:café猫🌍": 1})
	assert_int(actuator.calls).is_equal(1)
	assert_int(actuator.value).is_equal(2)

func test_in_place_ray_append_is_rejected_until_space_is_synchronized() -> void:
	var sensor: ScholaSensor = load("res://addons/schola/components/ray_cast_sensor_3d.gd").new()
	sensor.component_id = "rays"
	agent.add_child(sensor)
	var ray := RayCast3D.new()
	ray.name = "Ray"
	ray.target_position = Vector3(0, 0, -1)
	agent.add_child(ray)
	sensor.add_ray(NodePath("../Ray"))
	_actuator("a")
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	assert_bool(driver.call("initialize", environment).ok).is_true()
	sensor.rays.append(NodePath("../Ray"))
	assert_bool(sensor.get_configuration_errors().is_empty()).is_false()
	assert_bool(driver.call("reset", environment).ok).is_false()
	# Training environments initialize once; a new session must redefine spaces.
	var replacement: ComponentEnvironment = auto_free(ComponentEnvironment.new())
	environment.remove_child(agent)
	environment = replacement
	environment.add_child(agent)
	add_child(environment)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	# Reassignment intentionally runs the setter after an in-place array edit.
	sensor.rays = sensor.rays
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	assert_array(Array(sensor.space.shape)).contains_exactly([4])
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	sensor.add_ray(NodePath("../Ray"))
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	assert_array(Array(sensor.space.shape)).contains_exactly([6])

func test_velocity_sensor_reads_rotated_rigid_body_and_scaling() -> void:
	var sensor: ScholaSensor = load("res://addons/schola/components/velocity_sensor_3d.gd").new()
	sensor.component_id = "velocity"
	agent.add_child(sensor)
	var body := RigidBody3D.new()
	body.name = "Body"
	body.freeze = true
	body.rotation.y = PI / 2.0
	body.linear_velocity = Vector3(4, 2, 0)
	agent.add_child(body)
	sensor.body_path = NodePath("../Body")
	sensor.velocity_scale = 2.0
	sensor.axes = 1
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var result: Dictionary = driver.call("step", environment, {"A": {"00000000:a": 0}})
	assert_bool(result.ok).is_true()
	var values: PackedFloat32Array = result.states.A.observation["00000000:velocity"]
	assert_vector(Vector3(values[0], values[1], values[2])).is_equal_approx(Vector3(2, 0, 1), Vector3.ONE * 0.0001)
	sensor.local_frame = false
	sensor.axes = 0
	result = driver.call("step", environment, {"A": {"00000000:a": 0}})
	values = result.states.A.observation["00000000:velocity"]
	assert_vector(Vector3(values[0], values[1], values[2])).is_equal_approx(Vector3(2, 1, 0), Vector3.ONE * 0.0001)
	sensor.velocity_scale = 0.0
	assert_bool(sensor.get_configuration_errors().is_empty()).is_false()

func test_velocity_sensor_supports_character_body_and_rejects_missing_body() -> void:
	var sensor: ScholaSensor = load("res://addons/schola/components/velocity_sensor_3d.gd").new()
	agent.add_child(sensor)
	assert_bool(sensor.get_configuration_errors().is_empty()).is_false()
	var body := CharacterBody3D.new()
	body.name = "Body"
	body.velocity = Vector3(1, 2, 3)
	agent.add_child(body)
	sensor.body_path = NodePath("../Body")
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	assert_array(Array(sensor._observe())).contains_exactly([1.0, 2.0, 3.0])

func test_vehicle_actuator_smooths_controls_and_clears_them_on_reset() -> void:
	_sensor("s")
	var actuator: ScholaActuator = load("res://addons/schola/components/vehicle_actuator_3d.gd").new()
	actuator.component_id = "controls"
	agent.add_child(actuator)
	assert_bool(actuator.get_configuration_errors().is_empty()).is_false()
	var body := VehicleBody3D.new()
	body.name = "Car"
	body.freeze = true
	agent.add_child(body)
	actuator.body_path = NodePath("../Car")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var result: Dictionary = driver.call("step", environment, {"A": {"00000000:controls": PackedFloat32Array([1, 1])}})
	assert_bool(result.ok).is_true()
	assert_float(body.engine_force).is_greater(0.0).is_less(7500.0)
	assert_float(body.steering).is_less(0.0)
	assert_float(body.brake).is_equal(0.0)
	actuator.reset()
	assert_float(body.engine_force).is_equal(0.0)
	assert_float(body.steering).is_equal(0.0)
	result = driver.call("step", environment, {"A": {"00000000:controls": PackedFloat32Array([0, -1])}})
	assert_bool(result.ok).is_true()
	assert_float(body.brake).is_greater(0.0).is_less(30.0)
	assert_float(body.engine_force).is_equal(0.0)
	actuator.reset()
	assert_float(body.brake).is_equal(0.0)

func test_path_sensor_works_without_race_track_scripts() -> void:
	var sensor: ScholaSensor = load("res://addons/schola/components/path_sensor_3d.gd").new()
	agent.add_child(sensor)
	var path := Path3D.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, 10))
	agent.add_child(path)
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(2, 0, 5)
	agent.add_child(body)
	sensor.body_path = NodePath("../Body")
	sensor.path_path = NodePath("../Path")
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	var values: PackedFloat32Array = sensor._observe()
	assert_vector(Vector3(values[0], values[1], values[2])).is_equal_approx(Vector3(-2, 0, 0), Vector3.ONE * 0.01)
	assert_vector(Vector3(values[3], values[4], values[5])).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.01)
	sensor.location_scale = 2.0
	sensor.axes = 1
	values = sensor._observe()
	assert_vector(Vector3(values[0], values[1], values[2])).is_equal_approx(Vector3(0, 1, 0), Vector3.ONE * 0.01)
	sensor.path_path = NodePath("../Missing")
	assert_bool(sensor.get_configuration_errors().is_empty()).is_false()

func test_keyboard_demo_disables_training_endings_and_tilt_ignores_heading() -> void:
	var scene: Node = auto_free(load("res://examples/race_track/scenes/race_track_train.tscn").instantiate())
	add_child(scene)
	var env: RaceTrackEnvironment = scene.get_node("RaceTrackEnvironment")
	var car: VehicleBody3D = env.get_node("Car")
	car.rotation = Vector3(0, PI * 0.75, 0)
	car.global_position = Vector3(10000, 0, 10000)
	env.terminate_off_track = false
	env.maximum_steps = 0
	var state: Dictionary = env._get_step_result(null)
	assert_bool(state.terminated).is_false()
	assert_bool(state.truncated).is_false()
	car.rotation.z = PI / 2.0
	assert_bool(env._get_step_result(null).terminated).is_true()
	env.terminate_on_tilt = false
	assert_bool(env._get_step_result(null).terminated).is_false()
	env.terminate_off_track = true
	assert_bool(env._get_step_result(null).terminated).is_true()
