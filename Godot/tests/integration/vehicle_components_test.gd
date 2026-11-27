# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# The path sensor, velocity sensor and vehicle actuator that the RaceTrack
# example composes, checked on their own scenes.
extends GdUnitTestSuite

const PathSensor := preload("res://addons/schola/components/path_sensor_3d.gd")
const VelocitySensor := preload("res://addons/schola/components/velocity_sensor_3d.gd")
const VehicleActuator := preload("res://addons/schola/components/vehicle_actuator_3d.gd")

var world: Node3D
var agent: ScholaAgent


func before_test() -> void:
	world = auto_free(Node3D.new())
	agent = ScholaAgent.new()
	agent.name = "Agent"
	world.add_child(agent)
	add_child(world)


func _add(node: Node, node_name: String, parent: Node = null) -> Node:
	node.name = node_name
	(world if parent == null else parent).add_child(node)
	return node


func _straight_path() -> Path3D:
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, 100))
	return _add(path, "Path")


func _path_sensor() -> PathSensor:
	var sensor: PathSensor = _add(PathSensor.new(), "Track", agent)
	sensor.body_path = NodePath("../../Body")
	sensor.path_path = NodePath("../../Path")
	return sensor


func _assert_values(actual: Variant, expected: Array) -> void:
	var values := PackedFloat32Array(actual)
	assert_int(values.size()).is_equal(expected.size())
	for index in expected.size():
		assert_float(values[index]).is_equal_approx(expected[index], 0.001)


func test_path_sensor_space_follows_the_enabled_features() -> void:
	var sensor := PathSensor.new()
	assert_array(Array(sensor.space.shape)).contains_exactly([6])
	sensor.include_progress = true
	assert_array(Array(sensor.space.shape)).contains_exactly([7])
	assert_float(sensor.space.low[6]).is_equal(0.0)
	assert_float(sensor.space.high[6]).is_equal(1.0)
	sensor.has_y = false
	assert_array(Array(sensor.space.shape)).contains_exactly([5])
	sensor.include_location = false
	sensor.include_direction = false
	sensor.include_progress = false
	assert_int(sensor.get_value_count()).is_equal(0)
	sensor.free()


func test_path_sensor_reports_the_look_ahead_point_in_the_body_frame() -> void:
	_straight_path()
	var body: Node3D = _add(Node3D.new(), "Body")
	body.position = Vector3(2, 0, 10)
	var sensor := _path_sensor()
	sensor.axes = PathSensor.Axes.FORWARD_RIGHT_UP
	sensor.look_ahead = 5.0
	sensor.include_progress = true

	assert_array(Array(sensor.get_configuration_errors())).is_empty()
	# The point 15 m along the path is 5 m ahead and 2 m to the car's right; the path runs forward.
	_assert_values(sensor._observe(), [5.0, 2.0, 0.0, 1.0, 0.0, 0.0, 0.1])


func test_path_sensor_reports_direction_on_a_short_closed_curve() -> void:
	_add(Node3D.new(), "Body")
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.bake_interval = 0.01
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0.25, 0, 0))
	path.curve.add_point(Vector3(0.25, 0, 0.25))
	path.curve.add_point(Vector3(0, 0, 0.25))
	path.curve.closed = true
	_add(path, "Path")
	var sensor := _path_sensor()
	sensor.include_location = false

	_assert_values(sensor._observe(), [1.0, 0.0, 0.0])
	sensor.look_ahead = 0.875
	_assert_values(sensor._observe(), [sqrt(0.5), 0.0, -sqrt(0.5)])


func test_path_sensor_rejects_a_missing_path() -> void:
	_add(Node3D.new(), "Body")
	var sensor := _path_sensor()

	assert_str(" ".join(sensor.get_configuration_errors())).contains("path_path")
	assert_object(sensor._observe()).is_null()


func test_velocity_sensor_scales_and_selects_forward_right_up_components() -> void:
	var body: CharacterBody3D = _add(CharacterBody3D.new(), "Body")
	body.velocity = Vector3(3, 4, 8)
	var sensor: VelocitySensor = _add(VelocitySensor.new(), "Velocity", agent)
	sensor.body_path = NodePath("../../Body")
	sensor.axes = VelocitySensor.Axes.FORWARD_RIGHT_UP
	sensor.velocity_scale = 2.0

	assert_array(Array(sensor.get_configuration_errors())).is_empty()
	_assert_values(sensor._observe(), [4.0, -1.5, 2.0])
	sensor.has_y = false
	assert_array(Array(sensor.space.shape)).contains_exactly([2])
	_assert_values(sensor._observe(), [4.0, 2.0])
	sensor.bound = 1.0
	_assert_values(sensor._observe(), [1.0, 1.0])


func test_velocity_sensor_reads_velocity_in_the_body_frame() -> void:
	var body: CharacterBody3D = _add(CharacterBody3D.new(), "Body")
	body.rotation = Vector3(0, PI / 2, 0) # The body's forward (+Z) now points along world +X.
	body.velocity = Vector3(1, 0, 0)
	var sensor: VelocitySensor = _add(VelocitySensor.new(), "Velocity", agent)
	sensor.body_path = NodePath("../../Body")
	sensor.axes = VelocitySensor.Axes.FORWARD_RIGHT_UP

	_assert_values(sensor._observe(), [1.0, 0.0, 0.0])
	sensor.local_frame = false
	_assert_values(sensor._observe(), [0.0, -1.0, 0.0])


func test_velocity_sensor_rejects_a_body_without_velocity() -> void:
	_add(Node3D.new(), "Body")
	var sensor: VelocitySensor = _add(VelocitySensor.new(), "Velocity", agent)
	sensor.body_path = NodePath("../../Body")

	assert_str(" ".join(sensor.get_configuration_errors())).contains("body_path")
	assert_object(sensor._observe()).is_null()


func test_vehicle_actuator_space_follows_steering_and_pedal_mode() -> void:
	var actuator := VehicleActuator.new()
	assert_array(Array(actuator.space.low)).contains_exactly([-1.0, -1.0])
	assert_array(Array(actuator.space.high)).contains_exactly([1.0, 1.0])
	actuator.pedal_mode = VehicleActuator.PedalMode.SEPARATE
	assert_array(Array(actuator.space.low)).contains_exactly([-1.0, 0.0, 0.0])
	assert_array(Array(actuator.space.high)).contains_exactly([1.0, 1.0, 1.0])
	actuator.pedal_mode = VehicleActuator.PedalMode.NONE
	assert_array(Array(actuator.space.shape)).contains_exactly([1])
	actuator.has_steering = false
	assert_int(actuator.get_action_count()).is_equal(0)
	actuator.free()


func test_vehicle_actuator_drives_the_vehicle_and_resets() -> void:
	var car: VehicleBody3D = _add(VehicleBody3D.new(), "Car")
	var actuator: VehicleActuator = _add(VehicleActuator.new(), "Controls", agent)
	actuator.body_path = NodePath("../../Car")
	for rate in ["steering_rise_rate", "steering_fall_rate", "pedal_rise_rate", "pedal_fall_rate"]:
		actuator.set(rate, 1000000.0) # Reach each target in one step.

	assert_array(Array(actuator.get_configuration_errors())).is_empty()
	actuator._act(PackedFloat32Array([0.5, -0.5]))
	assert_float(car.steering).is_equal_approx(-0.5 * deg_to_rad(40.0), 0.0001)
	assert_float(car.engine_force).is_equal(0.0)
	assert_float(car.brake).is_equal_approx(15.0, 0.0001)

	actuator._act(PackedFloat32Array([0.0, 1.0]))
	assert_float(car.steering).is_equal(0.0)
	assert_float(car.engine_force).is_equal_approx(7500.0, 0.01)
	assert_float(car.brake).is_equal(0.0)

	actuator.reset()
	assert_float(car.engine_force).is_equal(0.0)


func test_vehicle_actuator_smooths_its_inputs() -> void:
	var car: VehicleBody3D = _add(VehicleBody3D.new(), "Car")
	var actuator: VehicleActuator = _add(VehicleActuator.new(), "Controls", agent)
	actuator.body_path = NodePath("../../Car")

	actuator._act(PackedFloat32Array([0.0, 1.0]))
	var first := car.engine_force
	actuator._act(PackedFloat32Array([0.0, 1.0]))
	assert_float(first).is_greater(0.0)
	assert_float(first).is_less(7500.0)
	assert_float(car.engine_force).is_greater(first)


func test_vehicle_actuator_rejects_a_missing_vehicle() -> void:
	var actuator: VehicleActuator = _add(VehicleActuator.new(), "Controls", agent)

	assert_str(" ".join(actuator.get_configuration_errors())).contains("body_path")
