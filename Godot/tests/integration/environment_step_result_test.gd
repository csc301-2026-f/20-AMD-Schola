# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends GdUnitTestSuite


class TestAgent extends ScholaAgent:
	var actions: int = 0

	func _act(_action: Variant) -> void:
		actions += 1
		get_parent().events.append("act:" + str(name))

	func _observe() -> Variant:
		get_parent().events.append("observe:" + str(name))
		return 0


class TestEnvironment extends ScholaEnvironment:
	var events: Array[String] = []
	var result: Variant = {"reward": 1}
	var results: Dictionary = {}
	var limit: int = 0
	var resets: int = 0
	var result_calls: int = 0
	var endings: int = 0

	func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
		resets += 1
		events.append("reset")

	func _get_step_result(agent: ScholaAgent) -> Variant:
		result_calls += 1
		events.append("result:" + str(agent.name))
		if limit > 0:
			return {"reward": 0, "truncated": get_episode_step() + 1 >= limit}
		return results.get(str(agent.name), result)


# Deliberately has no result or reset override.
class MissingResultEnvironment extends ScholaEnvironment:
	var events: Array[String] = []


var _driver: RefCounted


func before(
	_do_skip := not ClassDB.class_exists("ScholaEnvironmentTestDriver"),
	_skip_reason := "Build with integration_tests=yes to run the native adapter suite."
) -> void:
	pass


func before_test() -> void:
	assert_bool(ClassDB.class_exists("ScholaEnvironmentTestDriver"))\
		.override_failure_message("Build with integration_tests=yes to run the adapter suite.").is_true()
	_driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")


func after_test() -> void:
	_driver = null


func _add_agent(environment: ScholaEnvironment, agent_name: String) -> TestAgent:
	var agent := TestAgent.new()
	agent.name = agent_name
	var space := ScholaDiscreteSpace.new()
	space.n = 2
	agent.observation_space = space
	agent.action_space = space
	environment.add_child(agent)
	return agent


func _environment(two_agents: bool = false) -> TestEnvironment:
	var environment: TestEnvironment = auto_free(TestEnvironment.new())
	_add_agent(environment, "A")
	if two_agents:
		_add_agent(environment, "B")
	add_child(environment)
	environment.episode_ended.connect(func() -> void: environment.endings += 1)
	assert_bool(_driver.call("initialize", environment).ok).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()
	environment.events.clear()
	return environment


func test_minimal_result_defaults_and_reset_is_separate() -> void:
	var environment := _environment()
	assert_int(environment.resets).is_equal(1)
	assert_int(environment.result_calls).is_equal(0)
	var response: Dictionary = _driver.call("step", environment, {"A": 0})
	assert_bool(response.ok).is_true()
	assert_float(response.states.A.reward).is_equal(1.0)
	assert_bool(response.states.A.terminated).is_false()
	assert_bool(response.states.A.truncated).is_false()
	assert_dict(response.states.A.info).is_empty()
	assert_array(environment.events).contains_exactly(["act:A", "observe:A", "result:A"])
	assert_int(environment.result_calls).is_equal(1)


func test_nested_environment_has_an_inspector_warning_and_adapter_error() -> void:
	var outer := _environment()
	var grouping := Node.new()
	outer.add_child(grouping)
	var inner := TestEnvironment.new()
	inner.name = "NestedEnvironment"
	_add_agent(inner, "A")
	grouping.add_child(inner)
	var warnings: PackedStringArray = _driver.call("configuration_warnings", inner)
	assert_str("; ".join(warnings)).contains("Nested ScholaEnvironment nodes are unsupported")
	var result: Dictionary = _driver.call("initialize", inner)
	assert_bool(result.ok).is_false()
	assert_str(result.message).contains("Nested ScholaEnvironment nodes are unsupported")


func test_all_agents_act_before_observation_and_result() -> void:
	var environment := _environment(true)
	environment.results = {
		"A": {"reward": 2.5, "terminated": true, "info": {&"reason": &"goal"}},
		"B": {"reward": -1, "truncated": true},
	}
	var response: Dictionary = _driver.call("step", environment, {"B": 1, "A": 0})
	assert_bool(response.ok).is_true()
	assert_array(environment.events).contains_exactly([
		"act:A", "act:B", "observe:A", "result:A", "observe:B", "result:B"
	])
	assert_dict(response.states.A.info).is_equal({"reason": "goal"})
	assert_bool(response.states.A.terminated).is_true()
	assert_bool(response.states.B.truncated).is_true()
	assert_int(environment.endings).is_equal(1)
	assert_int(environment.get_episode_step()).is_equal(1)


func test_user_step_limit_and_reset_reactivate_agents() -> void:
	var environment := _environment()
	environment.limit = 2
	var first: Dictionary = _driver.call("step", environment, {"A": 0})
	assert_bool(first.states.A.truncated).is_false()
	var second: Dictionary = _driver.call("step", environment, {"A": 0})
	assert_bool(second.states.A.truncated).is_true()
	assert_int(environment.endings).is_equal(1)
	assert_bool(_driver.call("step", environment, {"A": 0}).ok).is_false()
	assert_bool(_driver.call("reset", environment).ok).is_true()
	assert_int(environment.get_episode_step()).is_equal(0)
	assert_int(environment.resets).is_equal(2)
	assert_bool(_driver.call("step", environment, {"A": 0}).states.A.truncated).is_false()


func test_no_automatic_limit_and_both_flags_are_preserved() -> void:
	var environment := _environment()
	for index in range(5):
		assert_bool(_driver.call("step", environment, {"A": 0}).states.A.truncated).is_false()
	environment.result = {"reward": 0, "terminated": true, "truncated": true}
	var response: Dictionary = _driver.call("step", environment, {"A": 0})
	assert_bool(response.states.A.terminated).is_true()
	assert_bool(response.states.A.truncated).is_true()


func test_missing_hook_fails_before_act_and_reset_hook_is_optional() -> void:
	var environment: MissingResultEnvironment = auto_free(MissingResultEnvironment.new())
	var agent := _add_agent(environment, "A")
	add_child(environment)
	assert_bool(_driver.call("initialize", environment).ok).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()
	var response: Dictionary = _driver.call("step", environment, {"A": 0})
	assert_bool(response.ok).is_false()
	assert_str(response.message).contains("_get_step_result() is not overridden")
	assert_int(agent.actions).is_equal(0)
	assert_int(environment.get_episode_step()).is_equal(0)
	assert_float(response.states.sentinel.reward).is_equal(123.0)


func test_invalid_results_are_rejected_without_partial_output() -> void:
	var environment := _environment(true)
	var invalid_results: Array = [
		null, 1, [], {}, {"reward": true}, {"reward": "1"},
		{"reward": NAN}, {"reward": INF}, {"reward": 1.0e100},
		{"reward": 0, "terminated": 1}, {"reward": 0, "truncated": null},
		{"reward": 0, "info": []}, {"reward": 0, "info": {"reason": 1}},
		{"reward": 0, "info": {1: "reason"}}, {"reward": 0, "truncatted": true},
		{"reward": 0, 1: "unknown"},
	]
	for invalid in invalid_results:
		assert_bool(_driver.call("reset", environment).ok).is_true()
		environment.results = {"A": {"reward": 1, "terminated": true}, "B": invalid}
		var response: Dictionary = _driver.call("step", environment, {"A": 0, "B": 0})
		assert_bool(response.ok).is_false()
		assert_str(response.message).contains("Agent 'B': _get_step_result()")
		assert_int(response.states.size()).is_equal(1)
		assert_float(response.states.sentinel.reward).is_equal(123.0)
		assert_int(environment.get_episode_step()).is_equal(0)
		assert_int(environment.endings).is_equal(0)
	# A valid retry also proves the failed batch did not mark A finished.
	environment.results = {}
	assert_bool(_driver.call("step", environment, {"A": 0, "B": 0}).ok).is_true()
