# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

class ComponentEnvironment extends ScholaEnvironment:
	func _get_step_result(_agent: ScholaAgent) -> Dictionary:
		return {"reward": 0}
class Sensor extends ScholaSensor:
	func _init() -> void:
		var discrete := ScholaDiscreteSpace.new()
		discrete.n = 2
		space = discrete
	func _observe() -> Variant:
		return 0
class Actuator extends ScholaActuator:
	func _init() -> void:
		var discrete := ScholaDiscreteSpace.new()
		discrete.n = 2
		space = discrete
	func _act(_action: Variant) -> void:
		pass

var driver: RefCounted
var environment: ComponentEnvironment
var agent: ScholaAgent

func before(_do_skip := not ClassDB.class_exists("ScholaEnvironmentTestDriver"), _skip_reason := "Build with integration_tests=yes.") -> void:
	pass

func before_test() -> void:
	driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")
	environment = auto_free(ComponentEnvironment.new())
	agent = ScholaAgent.new()
	agent.name = "A"
	environment.add_child(agent)
	add_child(environment)

func after_test() -> void:
	driver = null

func _component(component: Node) -> void:
	component.component_id = "c"
	agent.add_child(component)
	var other: Node = Actuator.new() if component is ScholaSensor else Sensor.new()
	other.component_id = "other"
	agent.add_child(other)

func _initialize() -> void:
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()

func _act(action: Variant) -> Dictionary:
	return driver.call("step", environment, {"A": {"00000000:c": action}})

func test_movement_axes_asymmetric_bounds_scale_gate_and_signal() -> void:
	var body := CharacterBody3D.new()
	body.name = "Body"
	body.rotation.y = PI / 2
	agent.add_child(body)
	var movement := ScholaMovementActuator3D.new()
	movement.body_path = NodePath("../Body")
	movement.enabled_axes = Vector3i(1, 0, 1)
	movement.symmetric_bounds = false
	movement.minimum_speed = -2
	movement.maximum_speed = 3
	movement.input_scale = 2
	movement.movement_enabled = false
	_component(movement)
	var emitted: Array[Vector3] = []
	movement.movement_input.connect(func(value: Vector3) -> void: emitted.append(value))
	_initialize()
	assert_bool(_act(PackedFloat32Array([-2, 3])).ok).is_true()
	assert_vector(body.velocity).is_equal(Vector3.ZERO)
	assert_vector(emitted[0]).is_equal(Vector3(-4, 0, 6))
	movement.force = true
	body.velocity.y = -10 # Gravity remains owned by the body's physics loop.
	assert_bool(_act(PackedFloat32Array([-2, 3])).ok).is_true()
	assert_vector(body.velocity).is_equal_approx(Vector3(6, -10, 4), Vector3.ONE * 0.0001)
	assert_bool(_act(PackedFloat32Array([-3, 3])).ok).is_false()
	assert_int(emitted.size()).is_equal(2)

func test_rotation_normalized_axes_use_pitch_yaw_roll_order() -> void:
	var target := Node3D.new()
	target.name = "Target"
	target.scale = Vector3(2, 1, 3)
	agent.add_child(target)
	var rotation := ScholaRotationActuator3D.new()
	rotation.target_path = NodePath("../Target")
	rotation.enabled_axes = Vector3i(1, 1, 0)
	rotation.lower_degrees = Vector3(-10, 20, 0)
	rotation.upper_degrees = Vector3(30, 60, 0)
	rotation.normalized_input = true
	_component(rotation)
	var emitted: Array[Vector3] = []
	rotation.rotation_input.connect(func(value: Vector3) -> void: emitted.append(value))
	_initialize()
	assert_bool(_act(PackedFloat32Array([0.5, 1])).ok).is_true()
	assert_vector(emitted[0]).is_equal(Vector3(10, 60, 0))
	var expected := Basis.from_euler(Vector3(deg_to_rad(10), deg_to_rad(60), 0))
	assert_bool(target.basis.orthonormalized().is_equal_approx(expected)).is_true()
	assert_vector(target.scale).is_equal_approx(Vector3(2, 1, 3), Vector3.ONE * 0.0001)
	assert_bool(_act(PackedFloat32Array([2, 0])).ok).is_false()
	assert_bool(target.basis.orthonormalized().is_equal_approx(expected)).is_true()

func test_teleport_flags_wait_direction_and_world_axes() -> void:
	var target := Node3D.new()
	target.name = "Target"
	target.rotation.y = PI / 2
	agent.add_child(target)
	var teleport := ScholaTeleportActuator3D.new()
	teleport.target_path = NodePath("../Target")
	teleport.x_directions = teleport.WAIT | teleport.POSITIVE | teleport.NEGATIVE
	teleport.z_directions = teleport.POSITIVE | teleport.NEGATIVE
	teleport.step = Vector3(2, 5, 3)
	_component(teleport)
	var emitted: Array[Vector3] = []
	teleport.teleport_input.connect(func(value: Vector3) -> void: emitted.append(value))
	_initialize()
	assert_bool(_act(PackedInt32Array([0, 1])).ok).is_true()
	assert_vector(target.global_position).is_equal(Vector3(0, 0, -3))
	assert_bool(_act(PackedInt32Array([1, 0])).ok).is_true()
	assert_vector(target.global_position).is_equal(Vector3(2, 0, 0))
	assert_bool(_act(PackedInt32Array([2, 0])).ok).is_true()
	assert_vector(target.global_position).is_equal(Vector3(0, 0, 3))
	assert_int(emitted.size()).is_equal(3)
	assert_bool(_act(PackedInt32Array([3, 0])).ok).is_false()
	assert_int(emitted.size()).is_equal(3)

func test_teleport_sweep_stops_before_obstacle() -> void:
	var body := CharacterBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	agent.add_child(body)
	var obstacle := StaticBody3D.new()
	obstacle.position.x = 3
	var obstacle_shape := CollisionShape3D.new()
	obstacle_shape.shape = BoxShape3D.new()
	obstacle.add_child(obstacle_shape)
	agent.add_child(obstacle)
	var teleport := ScholaTeleportActuator3D.new()
	teleport.target_path = NodePath("../Body")
	teleport.sweep = true
	teleport.step.x = 10
	_component(teleport)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_initialize()
	assert_bool(_act(PackedInt32Array([0])).ok).is_true()
	assert_float(body.position.x).is_between(1.9, 2.01)

func test_fake_camera_chw_padding_truncation_and_validation() -> void:
	var sensor := ScholaFakeCameraSensor.new()
	sensor.width = 2
	sensor.height = 1
	sensor.enabled_channels = 5 # R and B, two CHW planes.
	sensor.custom_image = PackedFloat32Array([0.2, 0.4, 0.6])
	_component(sensor)
	_initialize()
	var initial: Dictionary = driver.call("reset", environment)
	assert_array(Array(initial.states.A.observation["00000000:c"])).contains_exactly(Array(PackedFloat32Array([0.2, 0.4, 0.6, 0])))
	sensor.custom_image = PackedFloat32Array([1, 0, 0, 1, 99])
	var next: Dictionary = driver.call("step", environment, {"A": {"00000000:other": 0}})
	assert_bool(next.ok).is_true()
	assert_array(Array(next.states.A.observation["00000000:c"])).contains_exactly([1.0, 0.0, 0.0, 1.0])
	sensor.custom_image = PackedFloat32Array([-1])
	assert_bool(driver.call("reset", environment).ok).is_false()

func test_generated_ray_fan_circle_tags_and_exclusions() -> void:
	var origin := Node3D.new()
	origin.name = "Origin"
	agent.add_child(origin)
	var obstacle := StaticBody3D.new()
	obstacle.name = "Obstacle"
	obstacle.position.z = -5
	obstacle.add_to_group("wall")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	obstacle.add_child(shape)
	agent.add_child(obstacle)
	var sensor := ScholaRayCastSensor3D.new()
	sensor.use_generated_rays = true
	sensor.origin_path = NodePath("../Origin")
	sensor.num_rays = 1
	sensor.ray_length = 10
	sensor.tracked_tags = PackedStringArray(["wall", "enemy"])
	sensor.draw_debug = true
	_component(sensor)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_initialize()
	var result: Dictionary = driver.call("reset", environment)
	var observation: PackedFloat32Array = result.states.A.observation["00000000:c"]
	assert_array(Array(observation.slice(0, 3))).contains_exactly([1.0, 0.0, 1.0])
	assert_float(observation[3]).is_equal_approx(0.45, 0.001)
	assert_int(sensor.get_child_count(true)).is_equal(1)
	assert_bool(sensor.get_child(0, true).visible).is_true()
	sensor.draw_debug = false
	await get_tree().process_frame
	assert_bool(sensor.get_child(0, true).visible).is_false()
	sensor.exclude_paths = [NodePath("../Obstacle")]
	result = driver.call("reset", environment)
	assert_array(Array(result.states.A.observation["00000000:c"])).contains_exactly([0.0, 0.0, 0.0, 0.0])
	# Endpoint generation does not query physics or change the initialized layout.
	sensor.num_rays = 4
	sensor.ray_degrees = 360
	var endpoints := sensor.get_generated_endpoints()
	assert_int(endpoints.size()).is_equal(4)
	for index in 4:
		assert_float(endpoints[index].distance_to(endpoints[(index + 1) % 4])).is_equal_approx(sqrt(200), 0.001)
	sensor.num_rays = 3
	sensor.ray_degrees = 90
	endpoints = sensor.get_generated_endpoints()
	assert_float(endpoints[0].x).is_less(0)
	assert_vector(endpoints[1]).is_equal(Vector3(0, 0, -10))
	assert_float(endpoints[2].x).is_greater(0)

func test_generated_rays_observe_the_same_with_and_without_debug_lines() -> void:
	# The ray query is built once per observation, and debug segments are only
	# collected when drawn. Neither may change what the agent observes.
	var origin := Node3D.new()
	origin.name = "Origin"
	origin.position = Vector3(1, 0, 0)
	agent.add_child(origin)
	var obstacle := StaticBody3D.new()
	obstacle.position = Vector3(1, 0, -4)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	obstacle.add_child(shape)
	agent.add_child(obstacle)
	var sensor := ScholaRayCastSensor3D.new()
	sensor.use_generated_rays = true
	sensor.origin_path = NodePath("../Origin")
	sensor.num_rays = 5
	sensor.ray_degrees = 60
	sensor.ray_length = 10
	_component(sensor)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_initialize()

	sensor.draw_debug = false
	var hidden: PackedFloat32Array = driver.call("reset", environment).states.A.observation["00000000:c"]
	sensor.draw_debug = true
	var drawn: PackedFloat32Array = driver.call("reset", environment).states.A.observation["00000000:c"]
	assert_array(Array(drawn)).is_equal(Array(hidden))
	# Only the middle ray points straight at the box, so the fan must not
	# reuse one ray's end point for every ray.
	assert_float(hidden[4]).is_equal(1.0)
	assert_float(hidden[5]).is_equal_approx(0.35, 0.001)
	assert_float(hidden[0]).is_equal(0.0)
	assert_float(hidden[8]).is_equal(0.0)

	# Each observation starts its rays from where the origin is now.
	origin.position = Vector3(1, 0, -2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var closer: PackedFloat32Array = driver.call("reset", environment).states.A.observation["00000000:c"]
	assert_float(closer[5]).is_equal_approx(0.15, 0.001)


func test_invalid_component_parameters_are_rejected() -> void:
	var rotation := ScholaRotationActuator3D.new()
	_component(rotation)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	rotation.enabled_axes = Vector3i.ZERO
	assert_bool(rotation.get_configuration_errors().is_empty()).is_false()
	var fake: ScholaFakeCameraSensor = auto_free(ScholaFakeCameraSensor.new())
	fake.width = 0
	assert_bool(fake.get_configuration_errors().is_empty()).is_false()
	fake.width = 2048
	fake.height = 2048
	assert_bool(fake.get_configuration_errors().is_empty()).is_false()

func test_generated_ray_overflow_and_backward_only_movement_bounds() -> void:
	var origin := Node3D.new()
	origin.name = "Origin"
	agent.add_child(origin)
	var sensor := ScholaRayCastSensor3D.new()
	sensor.use_generated_rays = true
	sensor.origin_path = NodePath("../Origin")
	sensor.ray_length = 1e40 # Finite float64, but not a finite Godot Vector3.
	_component(sensor)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	assert_bool(sensor.get_configuration_errors().is_empty()).is_false()
	var movement: ScholaMovementActuator3D = auto_free(ScholaMovementActuator3D.new())
	movement.symmetric_bounds = false
	movement.minimum_speed = -3
	movement.maximum_speed = -1
	assert_str(movement.space.get_definition_error()).is_empty()
	assert_bool(movement.space.get_validation_error(PackedFloat32Array([-2, -2, -2])).is_empty()).is_true()
	movement.input_scale = 1e40
	assert_bool(movement._get_component_errors().has("Scaled speed bounds must fit finite Godot velocities.")).is_true()

func test_camera_components_run_through_local_onnx_inference() -> void:
	var body := CharacterBody3D.new()
	body.name = "Body"
	agent.add_child(body)
	var sensor := ScholaFakeCameraSensor.new()
	sensor.component_id = "camera"
	sensor.width = 1
	sensor.height = 1
	sensor.custom_image = PackedFloat32Array([0.25, 0.5, 0.75])
	agent.add_child(sensor)
	var movement := ScholaMovementActuator3D.new()
	movement.component_id = "move"
	movement.body_path = NodePath("../Body")
	agent.add_child(movement)
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = "res://tests/inference/fixtures/camera_components.onnx"
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = policy
	stepper.enabled = false
	add_child(stepper)
	assert_int(stepper.add_agent(agent)).is_equal(OK)
	assert_int(stepper.step()).is_equal(OK)
	assert_vector(body.velocity).is_equal(Vector3(0.25, 0.5, 0.75))
	sensor.custom_image = PackedFloat32Array([0.75, 0.5, 0.25])
	assert_int(stepper.step()).is_equal(OK)
	assert_vector(body.velocity).is_equal(Vector3(0.75, 0.5, 0.25))

func test_short_rays_far_from_origin_remain_valid() -> void:
	var origin := Node3D.new()
	origin.name = "Origin"
	origin.position.z = 2000
	agent.add_child(origin)
	var sensor := ScholaRayCastSensor3D.new()
	sensor.use_generated_rays = true
	sensor.origin_path = NodePath("../Origin")
	sensor.num_rays = 1
	sensor.ray_length = 0.01
	_component(sensor)
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	var ray := RayCast3D.new()
	ray.name = "Ray"
	ray.position.z = 2000
	ray.target_position = Vector3(0, 0, -0.01)
	agent.add_child(ray)
	sensor.use_generated_rays = false
	sensor.rays = [NodePath("../Ray")]
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	origin.position = Vector3(1e30, 0, 0)
	sensor.use_generated_rays = true
	sensor.ray_length = 1e30 # Finite endpoints but an overflowing distance.
	assert_bool(sensor.get_configuration_errors().is_empty()).is_false()

func test_movement_rejects_singular_basis_and_rotated_velocity_overflow() -> void:
	var body := CharacterBody3D.new()
	body.name = "Body"
	body.rotation.y = PI / 4
	agent.add_child(body)
	var movement := ScholaMovementActuator3D.new()
	movement.body_path = NodePath("../Body")
	movement.maximum_speed = 2.5e38 # Finite locally, but can overflow after rotation.
	_component(movement)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	assert_vector(body.velocity).is_equal(Vector3.ZERO)
	movement.maximum_speed = 1
	body.scale = Vector3(0, 1, 1)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	body.scale = Vector3(1e20, 1, 1e-20)
	assert_bool(driver.call("initialize", environment).ok).is_false()

func test_rotation_rejects_a_singular_target_before_dispatch() -> void:
	var target := Node3D.new()
	target.name = "Target"
	target.scale = Vector3(0, 1, 1)
	agent.add_child(target)
	var rotation := ScholaRotationActuator3D.new()
	rotation.target_path = NodePath("../Target")
	_component(rotation)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	target.scale = Vector3(1e20, 1, 1e-20)
	assert_bool(driver.call("initialize", environment).ok).is_false()

func test_teleport_rejects_world_position_overflow() -> void:
	var target := Node3D.new()
	target.name = "Target"
	target.position.x = 2.5e38
	agent.add_child(target)
	var teleport := ScholaTeleportActuator3D.new()
	teleport.target_path = NodePath("../Target")
	teleport.step.x = 2.5e38
	_component(teleport)
	assert_bool(driver.call("initialize", environment).ok).is_false()
