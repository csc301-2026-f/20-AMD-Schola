# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite


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
