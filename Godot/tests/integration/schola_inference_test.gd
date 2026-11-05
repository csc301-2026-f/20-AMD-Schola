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


func test_initialize_loads_the_model_by_itself() -> void:
	var policy := _policy("box_scale.onnx")
	assert_int(policy.initialize(_agent(3, 3, null))).is_equal(OK)
	assert_bool(policy.is_loaded()).is_true()

	var missing := _policy("does_not_exist.onnx")
	assert_int(missing.initialize(_agent(3, 3, null))).is_equal(ERR_FILE_NOT_FOUND)
	assert_str(missing.get_last_error()).starts_with("ScholaOnnxPolicy.load: ")


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


func test_last_error_is_cleared_by_the_next_call() -> void:
	var policy := _policy("box_scale.onnx")
	assert_int(policy.load()).is_equal(OK)
	assert_int(policy.initialize(_agent(3, 3, null))).is_equal(OK)

	assert_that(policy.infer(PackedFloat32Array([1.0]))).is_null()
	assert_str(policy.get_last_error()).starts_with("ScholaOnnxPolicy.infer: ")
	assert_that(policy.infer(PackedFloat32Array([1.0, 2.0, 3.0]))).is_not_null()
	assert_str(policy.get_last_error()).is_empty()


func test_copy_from_reports_a_state_of_another_size() -> void:
	var short_policy := _policy("counter.onnx")
	var long_policy := _policy("counter_seq.onnx")
	long_policy.max_state_sequence_length = 3
	for policy in [short_policy, long_policy]:
		assert_int(policy.load()).is_equal(OK)
		assert_int(policy.initialize(_agent(1, 2, null))).is_equal(OK)
	var state := short_policy.create_state()

	assert_int(state.copy_from(long_policy.create_state())).is_equal(ERR_INVALID_PARAMETER)
	assert_str(state.get_last_error()).starts_with("ScholaPolicyState.copy_from: ")


func test_initialize_reloads_after_the_model_path_changes() -> void:
	var policy := _policy("box_scale.onnx")
	var agent := _agent(3, 3, null)
	assert_int(policy.initialize(agent)).is_equal(OK)

	policy.model_path = FIXTURES + "does_not_exist.onnx"
	assert_int(policy.initialize(agent)).is_equal(ERR_FILE_NOT_FOUND)
	assert_bool(policy.is_loaded()).is_false()
	assert_bool(policy.is_initialized()).is_false()

	policy.model_path = FIXTURES + "box_scale.onnx"
	assert_int(policy.initialize(agent)).is_equal(OK)
	assert_array(_values(policy.infer(PackedFloat32Array([1.0, 2.0, 3.0])))).contains_exactly([2.0, 4.0, 6.0])


func test_initialize_applies_a_changed_sequence_length() -> void:
	var policy := _policy("counter_seq.onnx")
	var agent := _agent(1, 2, null)
	policy.max_state_sequence_length = 3
	assert_int(policy.initialize(agent)).is_equal(OK)
	assert_str(str(policy.create_state())).contains("3x2")

	policy.max_state_sequence_length = 5
	assert_int(policy.initialize(agent)).is_equal(OK)
	assert_str(str(policy.create_state())).contains("5x2")


func test_initialize_keeps_a_preloaded_model() -> void:
	var policy := _policy("counter.onnx")
	assert_int(policy.load()).is_equal(OK)
	var names := policy.get_input_names()
	assert_int(policy.initialize(_agent(1, 2, null))).is_equal(OK)
	assert_array(policy.get_input_names()).contains_exactly(names)


func test_reloading_keeps_the_policy_and_needs_initialize_again() -> void:
	var policy := _policy("box_scale.onnx")
	assert_int(policy.load()).is_equal(OK)
	assert_int(policy.initialize(_agent(3, 3, null))).is_equal(OK)

	assert_int(policy.load()).is_equal(OK)
	assert_bool(policy.is_loaded()).is_true()
	assert_bool(policy.is_initialized()).is_false()

	policy.model_path = FIXTURES + "does_not_exist.onnx"
	assert_int(policy.load()).is_equal(ERR_FILE_NOT_FOUND)
	assert_bool(policy.is_loaded()).is_false()


func test_stepper_drives_its_agents_every_step() -> void:
	var agent := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	add_child(stepper)
	assert_int(stepper.add_agent(agent)).is_equal(OK)

	assert_int(stepper.step()).is_equal(OK)
	assert_int(agent.actions.size()).is_equal(1)
	assert_array(_values(agent.actions[0])).contains_exactly([2.0, 4.0, 6.0])


func test_stepper_clamps_a_box_action_to_the_agent_space() -> void:
	var agent := _agent(3, 3, PackedFloat32Array([9.0, 1.0, -9.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	add_child(stepper)
	assert_int(stepper.add_agent(agent)).is_equal(OK)

	assert_int(stepper.step()).is_equal(OK)
	assert_array(_values(agent.actions[0])).contains_exactly([10.0, 2.0, -10.0])
	assert_array(_values(stepper.policy.infer(agent.observation))).contains_exactly([10.0, 2.0, -10.0])


func test_stepper_only_skips_the_agent_with_a_discrete_action_outside_its_space() -> void:
	var space := ScholaDiscreteSpace.new()
	space.n = 2
	var bad := _agent(4, 1, PackedFloat32Array([0.0, 0.0, 0.0, 9.0]))
	var good := _agent(4, 1, PackedFloat32Array([9.0, 0.0, 0.0, 0.0]))
	bad.action_space = space
	good.action_space = space
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("discrete.onnx")
	stepper.enabled = false
	add_child(stepper)
	assert_int(stepper.add_agent(bad)).is_equal(OK)
	assert_int(stepper.add_agent(good)).is_equal(OK)

	assert_int(stepper.step()).is_equal(ERR_INVALID_PARAMETER)
	assert_int(bad.actions.size()).is_equal(0)
	assert_array(good.actions).contains_exactly([0])
	assert_int(stepper.policy.infer(bad.observation)).is_equal(3)


func test_stepper_keeps_stepping_after_a_bad_observation() -> void:
	var messages: Array = []
	var bad := _agent(3, 3, PackedFloat32Array([1.0, 1.0, 1.0]))
	var good := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	stepper.inference_failed.connect(func(message: String) -> void: messages.append(message))
	add_child(stepper)
	assert_int(stepper.add_agent(bad)).is_equal(OK)
	assert_int(stepper.add_agent(good)).is_equal(OK)
	assert_int(stepper.step()).is_equal(OK)

	bad.observation = PackedFloat32Array([5.0])
	assert_int(stepper.step()).is_equal(ERR_INVALID_PARAMETER)
	assert_int(messages.size()).is_equal(1)
	assert_array(_values(bad.actions[1])).contains_exactly([2.0, 2.0, 2.0])
	assert_array(_values(good.actions[1])).contains_exactly([2.0, 4.0, 6.0])


func test_stepper_adds_the_agents_from_the_inspector_list() -> void:
	var agent := _agent(3, 3, PackedFloat32Array([1.0, 1.0, 1.0]))
	agent.name = "InspectorAgent"
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	stepper.agents = [NodePath("../InspectorAgent")]
	add_child(stepper)

	assert_int(stepper.step()).is_equal(OK)
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


func test_stepper_fails_after_a_reload_until_its_agents_are_added_again() -> void:
	var messages: Array = []
	var agent := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	stepper.inference_failed.connect(func(message: String) -> void: messages.append(message))
	add_child(stepper)
	assert_int(stepper.add_agent(agent)).is_equal(OK)

	assert_int(stepper.policy.load()).is_equal(OK)
	assert_int(stepper.step()).is_equal(ERR_UNCONFIGURED)
	assert_int(stepper.step()).is_equal(ERR_UNCONFIGURED)
	assert_int(messages.size()).is_equal(1)
	assert_int(agent.actions.size()).is_equal(0)

	assert_int(stepper.remove_agent(agent)).is_equal(1)
	assert_int(stepper.add_agent(agent)).is_equal(OK)
	assert_int(stepper.step()).is_equal(OK)
	assert_int(agent.actions.size()).is_equal(1)


func test_stepper_rejects_a_policy_change_during_a_step() -> void:
	var messages: Array = []
	var first := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var second := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	var original := _policy("box_scale.onnx")
	stepper.policy = original
	stepper.enabled = false
	stepper.inference_failed.connect(func(message: String) -> void: messages.append(message))
	add_child(stepper)
	assert_int(stepper.add_agent(first)).is_equal(OK)
	assert_int(stepper.add_agent(second)).is_equal(OK)

	first.on_observe = func() -> void: stepper.policy = _policy("box_scale.onnx")
	first.on_act = func() -> void: stepper.policy = _policy("box_scale.onnx")
	assert_int(stepper.step()).is_equal(OK)

	assert_object(stepper.policy).is_same(original)
	assert_int(messages.size()).is_equal(2)
	assert_str(messages[0]).contains("set_deferred")
	assert_int(first.actions.size()).is_equal(1)
	assert_int(second.actions.size()).is_equal(1)


func test_stepper_applies_a_deferred_policy_change_after_the_step() -> void:
	var agent := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	var replacement := _policy("box_scale.onnx")
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	add_child(stepper)
	assert_int(stepper.add_agent(agent)).is_equal(OK)

	agent.on_act = func() -> void: stepper.set_deferred("policy", replacement)
	assert_int(stepper.step()).is_equal(OK)
	await get_tree().process_frame

	assert_object(stepper.policy).is_same(replacement)


func test_stepper_reports_a_changed_policy() -> void:
	var messages: Array = []
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	stepper.inference_failed.connect(func(message: String) -> void: messages.append(message))
	add_child(stepper)
	assert_int(stepper.add_agent(_agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0])))).is_equal(OK)

	stepper.policy = _policy("box_scale.onnx")
	assert_int(messages.size()).is_equal(1)
	assert_str(messages[0]).starts_with("ScholaInferenceStepper.policy: ")


func test_stepper_forgets_a_freed_agent() -> void:
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy("box_scale.onnx")
	stepper.enabled = false
	add_child(stepper)
	var kept := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	var freed := _agent(3, 3, PackedFloat32Array([1.0, 2.0, 3.0]))
	assert_int(stepper.add_agent(kept)).is_equal(OK)
	assert_int(stepper.add_agent(freed)).is_equal(OK)

	freed.free()
	assert_int(stepper.step()).is_equal(OK)
	assert_int(kept.actions.size()).is_equal(1)


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
