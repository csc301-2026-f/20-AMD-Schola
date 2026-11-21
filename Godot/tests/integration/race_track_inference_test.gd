# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const SCENE := "res://examples/race_track/scenes/race_track_inference.tscn"
const TRAINED_MODEL := "res://examples/race_track/policies/race_track.onnx"
const EXPORTED_MODEL := "res://tests/inference/fixtures/schola_ppo_race_car.onnx"


func test_inference_scene_drives_the_car_with_a_schola_exported_policy() -> void:
	var scene: Node = auto_free(load(SCENE).instantiate())
	var stepper: ScholaInferenceStepper = scene.get_node("InferenceStepper")
	assert_str(stepper.policy.model_path).is_equal(TRAINED_MODEL)

	var policy := ScholaOnnxPolicy.new()
	policy.model_path = EXPORTED_MODEL
	stepper.policy = policy

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
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = EXPORTED_MODEL
	scene.get_node("InferenceStepper").policy = policy
	add_child(scene)

	for frame in 60:
		await get_tree().physics_frame
	var controls: RaceTrackControls = scene.get_node("Car/Agent/Controls")
	assert_object(scene.get_node("ActionDisplay").controls).is_same(controls)
	assert_float(absf(controls.action[0]) + absf(controls.action[1])).is_greater(0.0)
