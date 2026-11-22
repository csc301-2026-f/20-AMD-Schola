# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const ConfiguredAgent := preload("res://tests/integration/support/us4_test_agent.gd")

var _driver: RefCounted


class TestEnvironment extends ScholaEnvironment:
	func _get_step_result(_agent: ScholaAgent) -> Dictionary:
		return {"reward": 0.0}


func before_test() -> void:
	assert_bool(ClassDB.class_exists("ScholaEnvironmentTestDriver"))\
		.override_failure_message("Build with integration_tests=yes to inspect native editor warnings.")\
		.is_true()
	if ClassDB.class_exists("ScholaEnvironmentTestDriver"):
		_driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")


func after_test() -> void:
	_driver = null


func _environment() -> ScholaEnvironment:
	var environment: ScholaEnvironment = auto_free(TestEnvironment.new())
	add_child(environment)
	return environment


func _warnings(environment: ScholaEnvironment) -> PackedStringArray:
	return _driver.call("get_environment_warnings", environment)


func test_each_agent_has_one_summary_and_keeps_all_specific_warnings() -> void:
	if _driver == null:
		return
	var environment := _environment()
	var expected: Array[String] = []
	for agent_name in ["First", "Second"]:
		var agent := ScholaAgent.new()
		agent.name = agent_name
		environment.add_child(agent)
		expected.append("Agent '%s' (%s) has configuration warnings. Select the agent node for details." % [agent_name, agent_name])
		assert_array(_driver.call("get_agent_warnings", agent)).contains_exactly([
			"observation_space is not set",
			"action_space is not set",
			"Implement _observe() in this agent's script to return its observation.",
			"Implement _act(action) in this agent's script to apply an action.",
		])
	# Runtime diagnostics still include both resource errors per agent.
	assert_int(environment.get_configuration_errors().size()).is_equal(4)
	assert_str(environment.get_configuration_errors()[0]).contains("observation_space is not set")
	assert_str(environment.get_configuration_errors()[1]).contains("action_space is not set")
	assert_array(_warnings(environment)).contains_exactly(expected)


func test_healthy_agent_has_no_summary_and_fixed_agent_summary_disappears() -> void:
	if _driver == null:
		return
	var environment := _environment()
	var agent := ScholaAgent.new()
	agent.name = "Agent"
	environment.add_child(agent)
	assert_int(_warnings(environment).size()).is_equal(1)
	agent.set_script(ConfiguredAgent)
	agent.observation_space = _space()
	agent.action_space = _space()
	assert_array(_driver.call("get_agent_warnings", agent)).is_empty()
	assert_array(_warnings(environment)).is_empty()


func test_descendant_paths_are_reported_and_nested_environments_are_independent() -> void:
	if _driver == null:
		return
	var environment := _environment()
	var group := Node.new()
	group.name = "Group"
	environment.add_child(group)
	var agent := ScholaAgent.new()
	agent.name = "Agent"
	agent.agent_id = "player"
	group.add_child(agent)
	var nested := TestEnvironment.new()
	environment.add_child(nested)
	var nested_agent := ScholaAgent.new()
	nested_agent.name = "NestedAgent"
	nested.add_child(nested_agent)
	assert_array(_warnings(environment)).contains_exactly([
		"Agent 'player' (Group/Agent) has configuration warnings. Select the agent node for details.",
	])
	assert_array(_warnings(nested)).contains_exactly([
		"Agent 'NestedAgent' (NestedAgent) has configuration warnings. Select the agent node for details.",
	])


func test_environment_specific_warnings_remain_detailed() -> void:
	if _driver == null:
		return
	var environment: ScholaEnvironment = auto_free(ScholaEnvironment.new())
	add_child(environment)
	assert_array(_warnings(environment)).contains_exactly([
		"Implement _get_step_result(agent) in this environment's script to return reward and episode state.",
		"Add a ScholaAgent node below this environment.",
	])
	for agent_name in ["First", "Second"]:
		var agent: ScholaAgent = ConfiguredAgent.new()
		agent.observation_space = _space()
		agent.action_space = _space()
		agent.name = agent_name
		agent.agent_id = "duplicate"
		environment.add_child(agent)
	assert_array(_warnings(environment)).contains_exactly([
		"Implement _get_step_result(agent) in this environment's script to return reward and episode state.",
		"Duplicate agent ID 'duplicate' on 'First' and 'Second'. Set unique agent IDs or rename nodes that use the name fallback.",
	])


func _space() -> ScholaDiscreteSpace:
	var space := ScholaDiscreteSpace.new()
	space.n = 2
	return space
