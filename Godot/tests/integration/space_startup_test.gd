# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# US15 step 4: agents that define their spaces in code start up everywhere
# Inspector agents do: in the configuration checks, the environment adapter,
# the training host, and standalone inference.
extends GdUnitTestSuite

const TestEnvironment := preload("res://tests/integration/support/us4_test_environment.gd")
const FIXTURES := "res://tests/inference/fixtures/"

const STATUS_OK := 0
const STATUS_INVALID_DATA := 3
const STATUS_FAILED_PRECONDITION := 5
const AUTORESET_DISABLED := 2


# A playable agent whose spaces come only from _define_spaces(). `calls`
# shows how many times startup actually ran the callback.
class CodeAgent extends ScholaAgent:
	var returned: Variant = {}
	var calls := 0
	var observation: Variant = 0
	var last_action: Variant

	func _define_spaces() -> Variant:
		calls += 1
		return returned

	func _observe() -> Variant:
		return observation

	func _act(action: Variant) -> void:
		last_action = action


var _driver: RefCounted
var _previous_scene: Node


func before_test() -> void:
	_previous_scene = get_tree().current_scene
	if ClassDB.class_exists("ScholaEnvironmentTestDriver"):
		_driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")


func after_test() -> void:
	get_tree().current_scene = _previous_scene
	_driver = null


# --- Helpers ---------------------------------------------------------------


func _code_agent(returned: Variant) -> CodeAgent:
	var agent := CodeAgent.new()
	agent.name = "Coder"
	agent.agent_id = "coder"
	agent.returned = returned
	return agent


func _discrete_spaces() -> Dictionary:
	return {"observation": ScholaSpaces.discrete(3), "action": ScholaSpaces.discrete(3)}


func _box_spaces() -> Dictionary:
	return {"observation": ScholaSpaces.box([3], -10, 10), "action": ScholaSpaces.box([3], -10, 10)}


# An environment holding one code agent, already inside the scene tree.
func _environment_with(agent: CodeAgent, parent: Node = self) -> ScholaEnvironment:
	var environment := TestEnvironment.new() as ScholaEnvironment
	environment.name = "CodeEnvironment"
	environment.add_child(agent)
	parent.add_child(environment)
	return environment


# A fresh current scene, because the training host looks for environments there.
func _scene_root() -> Node:
	var root := auto_free(Node.new()) as Node
	root.name = "US15StartupRoot"
	get_tree().root.add_child(root)
	get_tree().current_scene = root
	return root


func _add_host(root: Node) -> ScholaTrainingHost:
	var host := ScholaTrainingHost.new()
	host.name = "TrainingHost"
	root.add_child(host)
	return host


func _policy() -> ScholaOnnxPolicy:
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = FIXTURES + "box_scale.onnx"
	return policy


func _require_driver() -> bool:
	assert_object(_driver)\
		.override_failure_message("Build with integration_tests=yes to run the environment adapter checks.")\
		.is_not_null()
	return _driver != null


# --- Configuration checks never need (or run) the callback ----------------


func test_code_agent_with_empty_inspector_fields_has_no_configuration_errors() -> void:
	var agent: CodeAgent = auto_free(_code_agent(_discrete_spaces()))

	assert_array(agent.get_configuration_errors()).is_empty()
	assert_int(agent.calls).is_equal(0)


func test_code_agent_ignores_invalid_inspector_fields() -> void:
	var agent: CodeAgent = auto_free(_code_agent(_discrete_spaces()))
	agent.observation_space = ScholaSpaces.discrete(0)

	assert_array(agent.get_configuration_errors()).is_empty()


func test_inspector_agent_still_reports_missing_spaces() -> void:
	var agent: ScholaAgent = auto_free(ScholaAgent.new())

	var errors := agent.get_configuration_errors()

	assert_array(errors).contains(["observation_space is not set", "action_space is not set"])


func test_environment_with_a_code_agent_passes_its_configuration_check() -> void:
	var agent := _code_agent(_discrete_spaces())
	var environment: ScholaEnvironment = auto_free(_environment_with(agent))

	assert_array(environment.get_configuration_errors()).is_empty()
	assert_int(agent.calls).is_equal(0)


# --- The environment adapter, used directly --------------------------------


func test_environment_adapter_starts_and_steps_a_code_agent() -> void:
	if not _require_driver():
		return
	var agent := _code_agent(_discrete_spaces())
	var environment: ScholaEnvironment = auto_free(_environment_with(agent))

	var initialized: Dictionary = _driver.call("initialize", environment)
	assert_bool(initialized.ok).override_failure_message(initialized.message).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()
	var stepped: Dictionary = _driver.call("step", environment, {"coder": 2})

	assert_bool(stepped.ok).override_failure_message(stepped.message).is_true()
	assert_int(agent.last_action).is_equal(2)
	assert_int(agent.calls).is_equal(1)


func test_environment_adapter_checks_values_against_the_callback_spaces() -> void:
	if not _require_driver():
		return
	var agent := _code_agent(_discrete_spaces())
	var environment: ScholaEnvironment = auto_free(_environment_with(agent))
	assert_bool(_driver.call("initialize", environment).ok).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()

	# Discrete(3) from the callback only allows 0, 1 and 2.
	var bad_action: Dictionary = _driver.call("step", environment, {"coder": 7})
	assert_bool(bad_action.ok).is_false()
	assert_str(bad_action.message).contains("outside [0, 3)")
	assert_object(agent.last_action).is_null()

	agent.observation = 5
	var bad_observation: Dictionary = _driver.call("step", environment, {"coder": 1})
	assert_bool(bad_observation.ok).is_false()
	assert_str(bad_observation.message).contains("_observe() returned a bad value")


func test_environment_adapter_reports_a_broken_callback_by_agent() -> void:
	if not _require_driver():
		return
	var agent := _code_agent({"observation": ScholaSpaces.discrete(3)})
	var environment: ScholaEnvironment = auto_free(_environment_with(agent))

	var result: Dictionary = _driver.call("initialize", environment)

	assert_bool(result.ok).is_false()
	assert_str(result.message).contains("Agent 'coder'")
	assert_str(result.message).contains("_define_spaces()[\"action\"] is missing")


# --- The training host ------------------------------------------------------


func test_training_host_starts_a_session_from_code_defined_spaces() -> void:
	var root := _scene_root()
	var spaces := _discrete_spaces()
	var agent := _code_agent(spaces)
	_environment_with(agent, root)
	var host := _add_host(root)

	assert_int(host.initialize_session()["status"]["code"]).is_equal(STATUS_OK)
	assert_int(agent.calls).is_equal(1)

	# Edits after session start don't reach training: it keeps the first answer.
	spaces.observation.n = 9
	agent.returned = {"observation": ScholaSpaces.discrete(4), "action": ScholaSpaces.discrete(4)}

	assert_int(host.set_autoreset_mode(AUTORESET_DISABLED)["status"]["code"]).is_equal(STATUS_OK)
	var definition := host.define()
	assert_int(definition["status"]["code"]).is_equal(STATUS_OK)
	var coder: Dictionary = definition["value"]["environments"][0]["agents"]["coder"]
	assert_int(coder["observation_space"]["n"]).is_equal(3)
	assert_int(coder["action_space"]["n"]).is_equal(3)

	assert_int(host.reset({})["status"]["code"]).is_equal(STATUS_OK)
	var stepped := host.step({"actions": [{"coder": 1}]})
	assert_int(stepped["status"]["code"]).override_failure_message(stepped["status"]["message"]).is_equal(STATUS_OK)
	assert_int(agent.last_action).is_equal(1)
	assert_int(agent.calls).is_equal(1)


func test_training_host_rejects_a_broken_callback_at_session_start_and_allows_retry() -> void:
	var root := _scene_root()
	var agent := _code_agent({"observation": ScholaSpaces.discrete(3)})
	_environment_with(agent, root)
	var host := _add_host(root)

	var failed := host.initialize_session()

	assert_int(failed["status"]["code"]).is_equal(STATUS_INVALID_DATA)
	assert_str(failed["status"]["message"]).contains("CodeEnvironment")
	assert_str(failed["status"]["message"]).contains("Agent 'coder'")
	assert_str(failed["status"]["message"]).contains("_define_spaces()[\"action\"] is missing")
	assert_int(host.define()["status"]["code"]).is_equal(STATUS_FAILED_PRECONDITION)

	agent.returned = _discrete_spaces()
	assert_int(host.initialize_session()["status"]["code"]).is_equal(STATUS_OK)


# --- Standalone inference (no environment) -----------------------------------


func test_policy_initializes_from_code_defined_spaces() -> void:
	var agent: CodeAgent = auto_free(_code_agent(_box_spaces()))
	add_child(agent)
	var policy := _policy()

	assert_int(policy.initialize(agent)).is_equal(OK)
	assert_array(Array(policy.infer(PackedFloat32Array([1.0, 2.0, 3.0])))).contains_exactly([2.0, 4.0, 6.0])
	assert_int(agent.calls).is_equal(1)


func test_stepper_drives_a_code_defined_agent() -> void:
	var agent: CodeAgent = auto_free(_code_agent(_box_spaces()))
	agent.observation = PackedFloat32Array([1.0, 2.0, 3.0])
	add_child(agent)
	var stepper: ScholaInferenceStepper = auto_free(ScholaInferenceStepper.new())
	stepper.policy = _policy()
	stepper.enabled = false
	add_child(stepper)

	assert_int(stepper.add_agent(agent)).is_equal(OK)
	assert_int(stepper.step()).is_equal(OK)

	assert_array(Array(agent.last_action)).contains_exactly([2.0, 4.0, 6.0])
	assert_int(agent.calls).is_equal(1)
