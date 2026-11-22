# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# US15 step 3: how an agent's define() picks, checks and keeps its spaces.
# Every test goes through ScholaEnvironmentTestDriver.define_agent(), which
# calls the same C++ define() that training and inference call.
extends GdUnitTestSuite

const INVALID_ARGUMENT := 1
const FAILED_PRECONDITION := 5


# An agent that builds its spaces in code. Each test sets `returned` to
# whatever _define_spaces() should hand back; `calls` counts how often it ran.
class CodeAgent extends ScholaAgent:
	var returned: ScholaSpaceDefinition
	var calls := 0
	var on_define := Callable()

	func _define_spaces() -> ScholaSpaceDefinition:
		calls += 1
		if on_define.is_valid():
			on_define.call()
		return returned


# Gets _define_spaces() only through inheritance.
class InheritedCodeAgent extends CodeAgent:
	pass


var _driver: RefCounted


func before_test() -> void:
	assert_bool(ClassDB.class_exists("ScholaEnvironmentTestDriver"))\
		.override_failure_message("Build with integration_tests=yes to run the space resolution suite.")\
		.is_true()
	_driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")


func after_test() -> void:
	_driver = null


# --- Helpers ---------------------------------------------------------------


func _define(agent: ScholaAgent) -> Dictionary:
	return _driver.call("define_agent", agent)


func _code_agent(returned: ScholaSpaceDefinition) -> CodeAgent:
	var agent: CodeAgent = auto_free(CodeAgent.new())
	agent.name = "Coder"
	agent.returned = returned
	return agent


func _spaces(observation: ScholaSpace, action: ScholaSpace) -> ScholaSpaceDefinition:
	return ScholaSpaceDefinition.create(observation, action)


func _assert_fails(result: Dictionary, code: int, reason: String) -> void:
	assert_bool(result.ok).override_failure_message("expected define() to fail with: " + reason).is_false()
	assert_int(result.code).is_equal(code)
	assert_str(result.message).starts_with("Agent 'Coder': ")
	assert_str(result.message).contains(reason)


# One arm joint: an angle reading plus a binary "touching" flag.
func _joint() -> ScholaDictSpace:
	return ScholaSpaces.dict({
		"angle": ScholaSpaces.box([1], -PI, PI),
		"touching": ScholaSpaces.multi_binary(1),
	})


# Repeats _joint() once per joint, named joint_0, joint_1, ...
func _arm(joint_count: int) -> ScholaDictSpace:
	var joints := {}
	for i in joint_count:
		joints["joint_%d" % i] = _joint()
	return ScholaSpaces.dict(joints)


# --- Where the spaces come from ------------------------------------------


func test_inspector_agent_uses_its_inspector_spaces() -> void:
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	agent.name = "Coder"
	agent.observation_space = ScholaSpaces.discrete(3)
	agent.action_space = ScholaSpaces.multi_discrete([2, 4])

	var result := _define(agent)

	assert_bool(result.ok).is_true()
	assert_dict(result.observation).is_equal(agent.observation_space.to_dictionary())
	assert_dict(result.action).is_equal(agent.action_space.to_dictionary())


func test_inspector_agent_with_a_missing_space_names_the_property() -> void:
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	agent.name = "Coder"
	agent.observation_space = ScholaSpaces.discrete(3)

	_assert_fails(_define(agent), FAILED_PRECONDITION, "action_space is not set")


func test_callback_supplies_both_spaces_when_inspector_is_empty() -> void:
	var observation := ScholaSpaces.box([4], -1, 1)
	var action := ScholaSpaces.discrete(5)
	var agent := _code_agent(_spaces(observation, action))

	var result := _define(agent)

	assert_bool(result.ok).is_true()
	assert_dict(result.observation).is_equal(observation.to_dictionary())
	assert_dict(result.action).is_equal(action.to_dictionary())
	assert_int(agent.calls).is_equal(1)


func test_inherited_callback_is_used() -> void:
	var agent: InheritedCodeAgent = auto_free(InheritedCodeAgent.new())
	agent.name = "Coder"
	agent.returned = _spaces(ScholaSpaces.discrete(2), ScholaSpaces.discrete(3))

	var result := _define(agent)

	assert_bool(result.ok).is_true()
	assert_int(result.action.n).is_equal(3)
	assert_int(agent.calls).is_equal(1)


func test_callback_wins_over_inspector_and_leaves_inspector_fields_alone() -> void:
	var agent := _code_agent(_spaces(ScholaSpaces.discrete(7), ScholaSpaces.discrete(8)))
	var inspector_observation := ScholaSpaces.discrete(2)
	var inspector_action := ScholaSpaces.discrete(2)
	agent.observation_space = inspector_observation
	agent.action_space = inspector_action

	var result := _define(agent)

	assert_bool(result.ok).is_true()
	assert_int(result.observation.n).is_equal(7)
	assert_int(result.action.n).is_equal(8)
	# The Inspector fields still hold what the developer assigned.
	assert_object(agent.observation_space).is_same(inspector_observation)
	assert_object(agent.action_space).is_same(inspector_action)


func test_broken_callback_never_falls_back_to_valid_inspector_spaces() -> void:
	var agent := _code_agent(ScholaSpaceDefinition.new())
	agent.observation_space = ScholaSpaces.discrete(2)
	agent.action_space = ScholaSpaces.discrete(2)

	_assert_fails(_define(agent), INVALID_ARGUMENT, "_define_spaces().observation is null")


func test_callback_wins_even_when_inspector_spaces_are_invalid() -> void:
	var agent := _code_agent(_spaces(ScholaSpaces.discrete(2), ScholaSpaces.discrete(3)))
	agent.observation_space = ScholaSpaces.discrete(0)

	assert_bool(_define(agent).ok).is_true()


# --- Reporting broken callback results ------------------------------------


func test_malformed_results_name_the_agent_and_the_problem() -> void:
	var ok := ScholaSpaces.discrete(2)
	var cycle := ScholaDictSpace.new()
	cycle.spaces = {"self": cycle}
	# Each case: [what _define_spaces() returns, part of the expected error].
	var cases := [
		[null, "_define_spaces() returned null"],
		[ScholaSpaceDefinition.new(), "_define_spaces().observation is null"],
		[_spaces(null, ok), "_define_spaces().observation is null"],
		[_spaces(ok, null), "_define_spaces().action is null"],
		[_spaces(ok, ScholaSpaces.box([2], 1, 0)), "_define_spaces().action: "],
		[_spaces(ok, ScholaSpaces.box([0], 0, 1)), "_define_spaces().action: "],
		[_spaces(ScholaSpaces.box_bounds([3], [0, 0], [1]), ok), "_define_spaces().observation: "],
		[_spaces(ScholaSpaces.dict({"arm": ScholaSpaces.discrete(0)}), ok), "must be positive"],
		[_spaces(cycle, ok), "Dict contains itself"],
	]
	for entry in cases:
		var agent := _code_agent(entry[0])
		_assert_fails(_define(agent), INVALID_ARGUMENT, entry[1])
	cycle.spaces = {}


# --- Resolving once and keeping the result --------------------------------


func test_spaces_are_resolved_once_and_reused() -> void:
	var agent := _code_agent(_spaces(ScholaSpaces.discrete(2), ScholaSpaces.discrete(3)))

	for i in 3:
		assert_bool(_define(agent).ok).is_true()

	assert_int(agent.calls).is_equal(1)


func test_failed_resolution_saves_nothing_and_can_be_retried() -> void:
	var agent := _code_agent(ScholaSpaceDefinition.new())
	assert_bool(_define(agent).ok).is_false()

	agent.returned = _spaces(ScholaSpaces.discrete(2), ScholaSpaces.discrete(3))
	var retry := _define(agent)
	assert_bool(retry.ok).is_true()
	assert_int(retry.action.n).is_equal(3)

	# The successful answer is now kept, so the callback doesn't run again.
	assert_bool(_define(agent).ok).is_true()
	assert_int(agent.calls).is_equal(2)


func test_editing_resources_after_resolution_does_not_change_saved_spaces() -> void:
	var observation := ScholaSpaces.discrete(3)
	var agent := _code_agent(_spaces(observation, ScholaSpaces.discrete(2)))
	assert_bool(_define(agent).ok).is_true()

	observation.n = 9
	agent.returned = _spaces(ScholaSpaces.discrete(4), ScholaSpaces.discrete(4))

	assert_int(_define(agent).observation.n).is_equal(3)


func test_changing_inspector_fields_after_resolution_does_not_change_saved_spaces() -> void:
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	agent.name = "Coder"
	agent.observation_space = ScholaSpaces.discrete(3)
	agent.action_space = ScholaSpaces.discrete(2)
	assert_bool(_define(agent).ok).is_true()

	agent.observation_space = ScholaSpaces.discrete(9)

	assert_int(_define(agent).observation.n).is_equal(3)


func test_editing_and_releasing_return_object_preserves_saved_snapshot() -> void:
	var definition := _spaces(ScholaSpaces.discrete(3), ScholaSpaces.discrete(2))
	var agent := _code_agent(definition)
	assert_bool(_define(agent).ok).is_true()
	definition.observation = ScholaSpaces.discrete(9)
	definition.action = null
	assert_int(_define(agent).observation.n).is_equal(3)
	assert_int(_define(agent).action.n).is_equal(2)
	agent.returned = null
	definition = null
	assert_int(_define(agent).action.n).is_equal(2)
	assert_int(agent.calls).is_equal(1)


func test_callback_that_calls_define_again_is_refused_without_breaking_the_outer_call() -> void:
	var agent := _code_agent(_spaces(ScholaSpaces.discrete(2), ScholaSpaces.discrete(3)))
	var inner_results: Array = []
	agent.on_define = func() -> void: inner_results.append(_define(agent))

	var outer := _define(agent)

	assert_bool(outer.ok).is_true()
	assert_int(agent.calls).is_equal(1)
	assert_int(inner_results.size()).is_equal(1)
	_assert_fails(inner_results[0], FAILED_PRECONDITION, "_define_spaces() must not cause define() to run again")


# --- Large and repeated spaces built with loops and helpers ---------------


func test_large_and_repeated_nested_spaces_built_with_helpers_resolve() -> void:
	var camera := ScholaSpaces.box([64, 64, 3], 0, 255, ScholaSpaces.UINT8)
	var observation := ScholaSpaces.dict({"camera": camera, "arm": _arm(6)})
	var action := ScholaSpaces.multi_discrete([3, 3, 3, 3, 3, 3])
	var agent := _code_agent(_spaces(observation, action))

	var result := _define(agent)

	assert_bool(result.ok).is_true()
	assert_dict(result.observation).is_equal(observation.to_dictionary())
	assert_array(result.observation.spaces.arm.spaces.keys()).contains_exactly(
		["joint_0", "joint_1", "joint_2", "joint_3", "joint_4", "joint_5"]
	)
	assert_str(result.observation.spaces.camera.dtype).is_equal(camera.to_dictionary().dtype)
