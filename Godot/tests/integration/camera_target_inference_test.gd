# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const SCENE := "res://examples/camera_target/scenes/camera_target_inference.tscn"
const TRAINED_MODEL := "res://examples/camera_target/policies/camera_target.onnx"
const EXPORTED_MODEL := "res://tests/inference/fixtures/schola_ppo_camera.onnx"
const EXPECTED := "res://tests/inference/fixtures/schola_ppo_camera.expected.txt"

var failures: Array[String] = []
var policy: ScholaOnnxPolicy


func test_inference_scene_turns_the_agent_by_the_exported_action_with_a_fake_camera() -> void:
	var lines := FileAccess.get_file_as_string(EXPECTED).split("\n")
	var scene := instantiate_with_exported_policy()
	var camera: Node = scene.get_node("CameraTarget/Agent/Camera")
	var fake := ScholaFakeCameraSensor.new()
	fake.name = "Camera"
	fake.width = 64
	fake.height = 64
	fake.custom_image = PackedFloat32Array(Array(lines[0].trim_prefix("observation ").split_floats(" ")))
	camera.replace_by(fake)
	camera.free()
	add_child(scene)

	for frame in 30:
		await get_tree().physics_frame
	assert_running(scene)

	var stepper: ScholaInferenceStepper = scene.get_node("InferenceStepper")
	var body: Node3D = scene.get_node("CameraTarget/Agent/Body")
	stepper.enabled = false
	body.rotation = Vector3.ZERO
	assert_int(stepper.step()).is_equal(OK)
	assert_float(body.rotation_degrees.y).is_equal_approx(lines[1].trim_prefix("action ").to_float(), 1e-5)


func test_inference_scene_turns_the_agent_with_the_real_camera(
	_do_skip := DisplayServer.get_name() == "headless",
	_skip_reason := "The real camera needs a rendering display."
) -> void:
	var scene := instantiate_with_exported_policy()
	add_child(scene)

	for frame in 60:
		await get_tree().physics_frame
		RenderingServer.force_draw(false)
	assert_running(scene)
	assert_float(scene.get_node("CameraTarget/Agent/Body").rotation_degrees.y).is_not_equal(0.0)


func instantiate_with_exported_policy() -> Node:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var stepper: ScholaInferenceStepper = scene.get_node("InferenceStepper")
	assert_str(stepper.policy.model_path).is_equal(TRAINED_MODEL)
	policy = ScholaOnnxPolicy.new()
	policy.model_path = EXPORTED_MODEL
	stepper.policy = policy
	failures.clear()
	stepper.inference_failed.connect(func(message: String) -> void: failures.append(message))
	return scene


func assert_running(scene: Node) -> void:
	var agent: ScholaAgent = scene.get_node("CameraTarget/Agent")
	assert_array(failures).is_empty()
	assert_bool(policy.is_initialized()).is_true()
	assert_array(Array(scene.get_node("InferenceStepper").get_configuration_errors())).is_empty()
	assert_array(Array(agent.get_configuration_errors())).is_empty()
	for component in ["Camera", "Rotation"]:
		assert_array(Array(agent.get_node(component).get_configuration_errors())).is_empty()
