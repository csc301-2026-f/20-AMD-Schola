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

func test_us5_core_configuration_properties_round_trip() -> void:
	# confirms Inspector/GDScript property bindings preserve configured values
	var environment := auto_free(ClassDB.instantiate("ScholaEnvironment") as Node)
	var agent := auto_free(ClassDB.instantiate("ScholaAgent") as Node)

	environment.set("max_episode_steps", 250)
	agent.set("agent_id", "player_1")
	agent.set("agent_type", "player")

	assert_int(environment.get("max_episode_steps")).is_equal(250)
	assert_str(agent.get("agent_id")).is_equal("player_1")
	assert_str(agent.get("agent_type")).is_equal("player")

	environment.set("max_episode_steps", -1)
	assert_int(environment.get("max_episode_steps")).is_equal(-1)


func test_agent_id_falls_back_to_current_node_name() -> void:
	var agent := auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"

	assert_str(agent.get("agent_id")).is_empty()
	assert_str(agent.call("get_resolved_agent_id")).is_equal("Player")

	agent.name = "Scout"
	assert_str(agent.call("get_resolved_agent_id")).is_equal("Scout")
	assert_str(agent.get("agent_id")).is_empty()


func test_explicit_agent_id_survives_rename_and_can_be_cleared() -> void:
	var agent := auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"
	agent.set("agent_id", "player_1")
	agent.name = "Scout"

	assert_str(agent.call("get_resolved_agent_id")).is_equal("player_1")
	assert_str(agent.get("agent_id")).is_equal("player_1")

	agent.set("agent_id", "")
	assert_str(agent.call("get_resolved_agent_id")).is_equal("Scout")


func test_duplicated_environments_preserve_agent_ids() -> void:
	var root := auto_free(Node.new())
	var environment := ClassDB.instantiate("ScholaEnvironment") as Node
	environment.name = "Arena"
	root.add_child(environment)
	var player := ClassDB.instantiate("ScholaAgent") as Node
	player.name = "Player"
	environment.add_child(player)
	var scout := ClassDB.instantiate("ScholaAgent") as Node
	scout.name = "Scout"
	scout.set("agent_id", "scout_1")
	environment.add_child(scout)

	var replica := environment.duplicate()
	replica.name = "ArenaCopy"
	root.add_child(replica)

	assert_str(replica.get_node("Player").call("get_resolved_agent_id")).is_equal(
		player.call("get_resolved_agent_id")
	)
	assert_str(replica.get_node("Scout").call("get_resolved_agent_id")).is_equal("scout_1")
	assert_str(replica.get_node("Player").get("agent_id")).is_empty()


func test_agent_id_fallback_remains_empty_after_scene_round_trip() -> void:
	var agent := auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"
	var scene := PackedScene.new()
	assert_int(scene.pack(agent)).is_equal(OK)
	var restored := auto_free(scene.instantiate())

	assert_str(restored.get("agent_id")).is_empty()
	restored.name = "Scout"
	assert_str(restored.call("get_resolved_agent_id")).is_equal("Scout")
