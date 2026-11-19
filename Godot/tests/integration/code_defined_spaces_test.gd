# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const ToolSpacesAgent := preload("res://tests/integration/support/us15_tool_spaces_agent.gd")
const InheritedToolSpacesAgent := preload("res://tests/integration/support/us15_inherited_tool_spaces_agent.gd")

const MISSING_HOOKS := [
	"Implement _observe() in this agent's script to return its observation.",
	"Implement _act(action) in this agent's script to apply an action.",
]

var _driver: RefCounted


func before_test() -> void:
	assert_bool(ClassDB.class_exists("ScholaEnvironmentTestDriver"))\
		.override_failure_message("Build with integration_tests=yes to inspect native editor warnings.")\
		.is_true()
	if ClassDB.class_exists("ScholaEnvironmentTestDriver"):
		_driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")


func after_test() -> void:
	_driver = null


class CodeSpacesAgent extends ScholaAgent:
	var definition_calls := 0

	func _define_spaces() -> Dictionary:
		definition_calls += 1
		return {}


class InheritedSpacesAgent extends CodeSpacesAgent:
	pass


func test_space_definition_hook_is_registered_as_virtual() -> void:
	var found := false
	for method in ClassDB.class_get_method_list("ScholaAgent", true):
		if method.name == "_define_spaces":
			found = true
			assert_int(int(method.flags) & METHOD_FLAG_VIRTUAL).is_not_equal(0)
	assert_bool(found).is_true()


func test_inspector_only_agent_has_no_code_definition() -> void:
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	assert_bool(agent.has_code_defined_spaces()).is_false()


func test_detection_recognizes_direct_and_inherited_hooks_without_execution() -> void:
	var direct: CodeSpacesAgent = auto_free(CodeSpacesAgent.new())
	var inherited: InheritedSpacesAgent = auto_free(InheritedSpacesAgent.new())
	for agent in [direct, inherited]:
		assert_bool(agent.has_code_defined_spaces()).is_true()
		assert_bool(agent.has_code_defined_spaces()).is_true()
		assert_int(agent.definition_calls).is_equal(0)


func test_metadata_queries_preserve_authored_resources_and_do_not_execute_hook() -> void:
	var agent: CodeSpacesAgent = auto_free(CodeSpacesAgent.new())
	var observation := ScholaDiscreteSpace.new()
	observation.n = 3
	var action := ScholaDiscreteSpace.new()
	action.n = 2
	agent.observation_space = observation
	agent.action_space = action

	assert_bool(agent.has_code_defined_spaces()).is_true()
	agent.get_configuration_errors()
	agent.update_configuration_warnings()

	assert_int(agent.definition_calls).is_equal(0)
	assert_object(agent.observation_space).is_same(observation)
	assert_object(agent.action_space).is_same(action)


func test_direct_and_inherited_warnings_skip_unused_spaces_and_preserve_hook_warnings() -> void:
	if _driver == null:
		return
	for script in [CodeSpacesAgent, InheritedSpacesAgent, ToolSpacesAgent, InheritedToolSpacesAgent]:
		var agent: ScholaAgent = auto_free(script.new())
		add_child(agent)
		for use_invalid_fields in [false, true]:
			if use_invalid_fields:
				agent.observation_space = ScholaSpaces.discrete(0)
				agent.action_space = ScholaSpaces.box([0], -1, 1)
			assert_array(agent.get_configuration_errors()).is_empty()
			assert_array(_driver.call("get_agent_warnings", agent)).contains_exactly(MISSING_HOOKS)
			agent.update_configuration_warnings()
		if agent is CodeSpacesAgent:
			assert_int(agent.definition_calls).is_equal(0)
		else:
			assert_int(agent.get_meta("definition_calls", 0)).is_equal(0)


func test_script_attachment_and_detachment_restore_inspector_warnings() -> void:
	if _driver == null:
		return
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	add_child(agent)
	var missing_spaces := ["observation_space is not set", "action_space is not set"]
	assert_array(_driver.call("get_agent_warnings", agent)).contains(missing_spaces)
	for script in [ToolSpacesAgent, InheritedToolSpacesAgent]:
		agent.set_script(script)
		assert_array(_driver.call("get_agent_warnings", agent)).contains_exactly(MISSING_HOOKS)
		agent.set_script(null)
		assert_bool(agent.has_code_defined_spaces()).is_false()
		assert_array(_driver.call("get_agent_warnings", agent)).contains(missing_spaces)
	assert_int(agent.get_meta("definition_calls", 0)).is_equal(0)


func test_changing_script_inheritance_updates_warning_contents_without_execution() -> void:
	if _driver == null:
		return
	var script := GDScript.new()
	script.source_code = '@tool\nextends "res://tests/integration/support/us15_tool_spaces_agent.gd"\n'
	assert_int(script.reload()).is_equal(OK)
	var agent: ScholaAgent = auto_free(ScholaAgent.new())
	agent.set_script(script)
	add_child(agent)
	assert_array(_driver.call("get_agent_warnings", agent)).contains_exactly(MISSING_HOOKS)

	# Simulate an editor reload that removes the inherited callback.
	script.source_code = "@tool\nextends ScholaAgent\n"
	assert_int(script.reload(true)).is_equal(OK)
	script.emit_changed()
	assert_bool(agent.has_code_defined_spaces()).is_false()
	assert_array(_driver.call("get_agent_warnings", agent)).contains([
		"observation_space is not set", "action_space is not set",
	])
	assert_int(agent.get_meta("definition_calls", 0)).is_equal(0)
