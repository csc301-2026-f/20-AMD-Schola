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

	var environment: Node = auto_free(ClassDB.instantiate("ScholaEnvironment") as Node)
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)

	assert_bool(is_instance_valid(environment)).is_true()
	assert_bool(is_instance_valid(agent)).is_true()
	assert_str(environment.get_class()).is_equal("ScholaEnvironment")
	assert_str(agent.get_class()).is_equal("ScholaAgent")


func test_us5_agent_type_property_round_trips() -> void:
	# confirms the currently bound US5 Inspector property reaches native state
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)

	agent.set("agent_type", "scout")

	assert_str(agent.get("agent_type")).is_equal("scout")

func test_us5_core_configuration_properties_round_trip() -> void:
	# confirms Inspector/GDScript property bindings preserve configured values
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)

	agent.set("agent_id", "player_1")
	agent.set("agent_type", "player")

	assert_str(agent.get("agent_id")).is_equal("player_1")
	assert_str(agent.get("agent_type")).is_equal("player")


func test_environment_has_no_builtin_episode_step_limit() -> void:
	var environment: Node = auto_free(ClassDB.instantiate("ScholaEnvironment") as Node)

	assert_bool(environment.has_method("set_max_episode_steps")).is_false()
	assert_bool(environment.has_method("get_max_episode_steps")).is_false()
	for property in environment.get_property_list():
		assert_str(str(property.name)).is_not_equal("max_episode_steps")


func test_agent_id_falls_back_to_current_node_name() -> void:
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"

	assert_str(agent.get("agent_id")).is_empty()
	assert_str(agent.call("get_resolved_agent_id")).is_equal("Player")

	agent.name = "Scout"
	assert_str(agent.call("get_resolved_agent_id")).is_equal("Scout")
	assert_str(agent.get("agent_id")).is_empty()


func test_explicit_agent_id_survives_rename_and_can_be_cleared() -> void:
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"
	agent.set("agent_id", "player_1")
	agent.name = "Scout"

	assert_str(agent.call("get_resolved_agent_id")).is_equal("player_1")
	assert_str(agent.get("agent_id")).is_equal("player_1")

	agent.set("agent_id", "")
	assert_str(agent.call("get_resolved_agent_id")).is_equal("Scout")


func test_duplicated_environments_preserve_agent_ids() -> void:
	var root: Node = auto_free(Node.new())
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
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"
	var scene := PackedScene.new()
	assert_int(scene.pack(agent)).is_equal(OK)
	var restored: Node = auto_free(scene.instantiate())

	assert_str(restored.get("agent_id")).is_empty()
	restored.name = "Scout"
	assert_str(restored.call("get_resolved_agent_id")).is_equal("Scout")


func test_empty_agent_type_tracks_resolved_agent_id() -> void:
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"
	assert_str(agent.call("get_resolved_agent_type")).is_equal("Player")

	agent.name = "Scout"
	assert_str(agent.call("get_resolved_agent_type")).is_equal("Scout")
	agent.set("agent_id", "player_1")
	assert_str(agent.call("get_resolved_agent_type")).is_equal("player_1")
	agent.set("agent_id", "")
	assert_str(agent.call("get_resolved_agent_type")).is_equal("Scout")
	assert_str(agent.get("agent_type")).is_empty()


func test_explicit_agent_type_takes_precedence_and_can_be_cleared() -> void:
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"
	agent.set("agent_type", "shared_policy")
	agent.set("agent_id", "player_1")
	agent.name = "Scout"

	assert_str(agent.call("get_resolved_agent_type")).is_equal("shared_policy")
	assert_str(agent.get("agent_type")).is_equal("shared_policy")
	assert_str(agent.call("get_resolved_agent_id")).is_equal("player_1")

	agent.set("agent_type", "")
	assert_str(agent.call("get_resolved_agent_type")).is_equal("player_1")


func test_agent_type_fallback_remains_empty_after_scene_round_trip() -> void:
	var agent: Node = auto_free(ClassDB.instantiate("ScholaAgent") as Node)
	agent.name = "Player"
	# Resolving the default must not store it as an explicit policy-sharing label.
	assert_str(agent.call("get_resolved_agent_type")).is_equal("Player")
	var scene := PackedScene.new()
	assert_int(scene.pack(agent)).is_equal(OK)
	var restored: Node = auto_free(scene.instantiate())

	assert_str(restored.get("agent_type")).is_empty()
	restored.set("agent_id", "player_2")
	assert_str(restored.call("get_resolved_agent_type")).is_equal("player_2")


func test_duplicate_ids_are_scoped_to_the_nearest_environment() -> void:
	var environment: ScholaEnvironment = auto_free(ScholaEnvironment.new())
	var first := ScholaAgent.new()
	first.name = "First"
	first.agent_id = "shared"
	var second := ScholaAgent.new()
	second.name = "Second"
	second.agent_id = "shared"
	var space := ScholaDiscreteSpace.new()
	space.n = 2
	for agent in [first, second]:
		agent.observation_space = space
		agent.action_space = space
		environment.add_child(agent)
	add_child(environment)

	var errors := "; ".join(environment.get_configuration_errors())
	assert_str(errors).contains("Duplicate agent ID 'shared'")
	assert_str(errors).contains("First")
	assert_str(errors).contains("Second")

	var nested := ScholaEnvironment.new()
	environment.add_child(nested)
	second.reparent(nested)
	assert_bool(environment.get_configuration_errors().is_empty()).is_true()
	assert_bool(nested.get_configuration_errors().is_empty()).is_true()
