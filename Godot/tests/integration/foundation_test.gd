# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

class_name FoundationIntegrationTest
extends GdUnitTestSuite


func test_runtime_extension_is_registered() -> void:
	assert_bool(ClassDB.class_exists("ScholaRuntimeProbe")).is_true()


func test_training_extension_is_registered() -> void:
	assert_bool(ClassDB.class_exists("ScholaTrainingProbe")).is_true()


func test_us5_nodes_are_registered_and_instantiable() -> void:
	# confirms the active extension exposes usable US5 node classes
	assert_bool(ClassDB.class_exists("ScholaEnvironment")).is_true()
	assert_bool(ClassDB.class_exists("ScholaAgent")).is_true()

	var environment := auto_free(ClassDB.instantiate("ScholaEnvironment") as Node)
	var agent := auto_free(ClassDB.instantiate("ScholaAgent") as Node)

	assert_bool(is_instance_valid(environment)).is_true()
	assert_bool(is_instance_valid(agent)).is_true()
	assert_str(environment.get_class()).is_equal("ScholaEnvironment")
	assert_str(agent.get_class()).is_equal("ScholaAgent")


func test_us5_agent_type_property_round_trips() -> void:
	# confirms the currently bound US5 Inspector property reaches native state
	var agent := auto_free(ClassDB.instantiate("ScholaAgent") as Node)

	agent.set("agent_type", "scout")

	assert_str(agent.get("agent_type")).is_equal("scout")
