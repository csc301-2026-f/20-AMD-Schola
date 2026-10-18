# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

class_name ScholaInferenceTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/inference/fixtures/"
const TestAgent := preload("res://tests/integration/support/inference_test_agent.gd")


func _agent(observation_size: int, action_size: int, value: Variant) -> ScholaAgent:
	var agent: ScholaAgent = auto_free(TestAgent.new())
	agent.setup(observation_size, action_size, value)
	add_child(agent)
	return agent


func _policy(file: String) -> ScholaOnnxPolicy:
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = FIXTURES + file
	return policy


func _values(value: Variant) -> Array:
	return Array(value)


func test_stepper_is_registered() -> void:
	assert_bool(ClassDB.class_exists("ScholaInferenceStepper")).is_true()


func test_infer_runs_the_model_on_a_gdscript_value() -> void:
	var policy := _policy("box_scale.onnx")
	assert_int(policy.load()).is_equal(OK)
	assert_int(policy.initialize(_agent(3, 3, null))).is_equal(OK)
	assert_bool(policy.is_initialized()).is_true()

	var action: Variant = policy.infer(PackedFloat32Array([1.0, 2.0, 3.0]))
	assert_array(_values(action)).contains_exactly([2.0, 4.0, 6.0])


func test_initialize_rejects_an_agent_whose_spaces_do_not_fit() -> void:
	var policy := _policy("box_scale.onnx")
	assert_int(policy.load()).is_equal(OK)
	assert_int(policy.initialize(_agent(2, 3, null))).is_equal(ERR_INVALID_DATA)
	assert_str(policy.get_last_error()).contains("obs")
	assert_bool(policy.is_initialized()).is_false()


func test_infer_keeps_memory_in_the_state() -> void:
	var policy := _policy("counter.onnx")
	assert_int(policy.load()).is_equal(OK)
	assert_int(policy.initialize(_agent(1, 2, null))).is_equal(OK)
	var state := policy.create_state()
	var observation := PackedFloat32Array([0.0])

	for expected in [0.0, 1.0, 2.0]:
		assert_array(_values(policy.infer(observation, state))).contains_exactly([expected, expected])
	state.reset()
	assert_array(_values(policy.infer(observation, state))).contains_exactly([0.0, 0.0])


func test_infer_needs_a_state_for_a_model_with_memory() -> void:
	var policy := _policy("counter.onnx")
	assert_int(policy.load()).is_equal(OK)
	assert_int(policy.initialize(_agent(1, 2, null))).is_equal(OK)

	assert_that(policy.infer(PackedFloat32Array([0.0]))).is_null()
	assert_str(policy.get_last_error()).contains("create_state()")


func test_stepper_drives_its_agents_every_step() -> void:
	var agent := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	add_child(stepper)
	assert_int(stepper.add_agent(agent)).is_equal(OK)

	assert_bool(stepper.step()).is_true()
	assert_int(agent.actions.size()).is_equal(1)
	assert_array(_values(agent.actions[0])).contains_exactly([2.0, 4.0, 6.0])


func test_stepper_adds_the_agents_from_the_inspector_list() -> void:
	var agent := _agent(3, 3, PackedFloat32Array([1.0, 1.0, 1.0]))
	agent.name = "InspectorAgent"
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	stepper.agents = [NodePath("../InspectorAgent")]
	add_child(stepper)

	assert_bool(stepper.step()).is_true()
	assert_int(agent.actions.size()).is_equal(1)


func test_stepper_keeps_a_state_per_agent() -> void:
	var first := _agent(1, 2, PackedFloat32Array([0.0]))
	var second := _agent(1, 2, PackedFloat32Array([0.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("counter.onnx")
	stepper.enabled = false
	add_child(stepper)
	assert_int(stepper.add_agent(first)).is_equal(OK)
	stepper.step()
	stepper.step()
	assert_int(stepper.add_agent(second)).is_equal(OK)
	stepper.step()

	assert_array(_values(first.actions[2])).contains_exactly([2.0, 2.0])
	assert_array(_values(second.actions[0])).contains_exactly([0.0, 0.0])

	stepper.reset_state(first)
	stepper.step()
	assert_array(_values(first.actions[3])).contains_exactly([0.0, 0.0])
	assert_array(_values(second.actions[1])).contains_exactly([1.0, 1.0])

	assert_int(stepper.remove_agent(first)).is_equal(1)
	stepper.step()
	assert_int(first.actions.size()).is_equal(4)


func test_stepper_reports_errors_through_its_signal() -> void:
	var messages: Array = []
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.inference_failed.connect(func(message: String) -> void: messages.append(message))
	add_child(stepper)

	assert_int(stepper.add_agent(_agent(3, 3, null))).is_equal(ERR_UNCONFIGURED)
	assert_int(messages.size()).is_equal(1)
	assert_str(messages[0]).contains("policy")


func test_stepper_warns_about_missing_configuration() -> void:
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.agents = [NodePath("missing")]
	add_child(stepper)

	var errors := stepper.get_configuration_errors()
	assert_str(errors[0]).contains("policy")
	assert_str(errors[1]).contains("missing")
