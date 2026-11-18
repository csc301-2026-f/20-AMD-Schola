# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

class ComponentEnvironment extends ScholaEnvironment:
	func _get_step_result(_agent: ScholaAgent) -> Dictionary:
		return {"reward": 0}
class Actuator extends ScholaActuator:
	func _init() -> void:
		var discrete := ScholaDiscreteSpace.new()
		discrete.n = 2
		space = discrete
	func _act(_value: Variant) -> void:
		pass

func before(
	_do_skip := DisplayServer.get_name() == "headless" or not ClassDB.class_exists("ScholaEnvironmentTestDriver"),
	_skip_reason := "Needs integration_tests=yes and a rendering display; run with --rendering-method gl_compatibility."
) -> void:
	pass

func test_color_and_linear_depth_readback_through_native_dispatch() -> void:
	var environment: ComponentEnvironment = auto_free(ComponentEnvironment.new())
	var agent := ScholaAgent.new()
	agent.name = "A"
	environment.add_child(agent)
	var color := SubViewport.new()
	color.name = "Color"
	color.size = Vector2i(2, 2)
	color.disable_3d = true
	color.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	agent.add_child(color)
	# RGBA channels, row-major within each channel plane.
	for y in 2:
		for x in 2:
			var rect := ColorRect.new()
			rect.position = Vector2(x, y)
			rect.size = Vector2.ONE
			rect.color = [Color.RED, Color.GREEN, Color.BLUE, Color.WHITE][y * 2 + x]
			color.add_child(rect)
	var depth := SubViewport.new()
	depth.name = "Depth"
	depth.size = Vector2i(2, 2)
	depth.own_world_3d = true
	depth.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	agent.add_child(depth)
	var camera := Camera3D.new()
	camera.current = true
	depth.add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.mesh.size = Vector2(10, 10)
	mesh.position.z = -2
	var material := ShaderMaterial.new()
	material.shader = load("res://addons/schola/components/linear_depth.gdshader")
	material.set_shader_parameter("depth_range", 4.0)
	mesh.material_override = material
	depth.add_child(mesh)
	var sensor := ScholaCameraSensor.new()
	sensor.component_id = "camera"
	sensor.width = 2
	sensor.height = 2
	sensor.enabled_channels = 5 # R then B.
	sensor.viewport_path = NodePath("../Color")
	sensor.depth_viewport_path = NodePath("../Depth")
	sensor.capture_mode = ScholaCameraSensor.CaptureMode.COLOR_DEPTH
	agent.add_child(sensor)
	var depth_sensor := ScholaCameraSensor.new()
	depth_sensor.component_id = "depth"
	depth_sensor.width = 2
	depth_sensor.height = 2
	depth_sensor.capture_mode = ScholaCameraSensor.CaptureMode.DEPTH
	depth_sensor.enabled_channels = 0
	depth_sensor.depth_viewport_path = NodePath("../Depth")
	agent.add_child(depth_sensor)
	var alpha_sensor := ScholaCameraSensor.new()
	alpha_sensor.component_id = "alpha"
	alpha_sensor.width = 2
	alpha_sensor.height = 2
	alpha_sensor.enabled_channels = 8
	alpha_sensor.viewport_path = NodePath("../Color")
	agent.add_child(alpha_sensor)
	var actuator := Actuator.new()
	actuator.component_id = "a"
	agent.add_child(actuator)
	add_child(environment)
	for frame in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var driver: RefCounted = ClassDB.instantiate("ScholaEnvironmentTestDriver")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	var response: Dictionary = driver.call("reset", environment)
	assert_bool(response.ok).is_true()
	var values: PackedFloat32Array = response.states.A.observation["00000000:camera"]
	assert_int(values.size()).is_equal(12)
	assert_array(Array(values.slice(0, 8))).contains_exactly([1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0])
	for value in values.slice(8):
		assert_float(value).is_equal_approx(0.5, 0.01)
	for value in response.states.A.observation["00000001:depth"]:
		assert_float(value).is_equal_approx(0.5, 0.01)
	assert_array(Array(response.states.A.observation["00000002:alpha"])).contains_exactly([1.0, 1.0, 1.0, 1.0])
	# The next successful capture must reflect the new completed render.
	(color.get_child(0) as ColorRect).color = Color.BLACK
	mesh.position.z = -1
	for frame in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	response = driver.call("step", environment, {"A": {"00000000:a": 0}})
	assert_bool(response.ok).is_true()
	values = response.states.A.observation["00000000:camera"]
	assert_array(Array(values.slice(0, 8))).contains_exactly([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0])
	for value in values.slice(8):
		assert_float(value).is_equal_approx(0.25, 0.01)
	# A viewport resize after define must fail before publishing a wrong layout.
	color.size = Vector2i(4, 2)
	assert_bool(driver.call("reset", environment).ok).is_false()
