# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

class_name TrainingHostIntegrationTest
extends GdUnitTestSuite

const TestAgent := preload("res://tests/integration/support/us4_test_agent.gd")
const TestEnvironment := preload("res://tests/integration/support/us4_test_environment.gd")

const STATUS_OK := 0
const STATUS_NOT_FOUND := 2
const STATUS_INVALID_DATA := 3
const STATUS_FAILED_PRECONDITION := 5

const AUTORESET_SAME_STEP := 0
const AUTORESET_NEXT_STEP := 1
const AUTORESET_DISABLED := 2


func _test_root() -> Node:
	var root := auto_free(Node.new()) as Node
	root.name = "US4TestRoot"
	get_tree().current_scene.add_child(root)
	return root


func _space() -> ScholaDiscreteSpace:
	var space := ScholaDiscreteSpace.new()
	space.n = 3
	return space


func _add_environment(root: Node, environment_name: String, agent_id: String) -> ScholaEnvironment:
	var environment := TestEnvironment.new() as ScholaEnvironment
	environment.name = environment_name
	_add_agent(environment, agent_id, agent_id)
	root.add_child(environment)
	return environment


func _add_agent(environment: ScholaEnvironment, node_name: String, agent_id: String) -> ScholaAgent:
	var agent := TestAgent.new() as ScholaAgent
	agent.name = node_name
	agent.agent_id = agent_id
	agent.observation_space = _space()
	agent.action_space = _space()
	environment.add_child(agent)
	return agent


func _add_host(root: Node) -> ScholaTrainingHost:
	var host := ScholaTrainingHost.new()
	host.name = "TrainingHost"
	root.add_child(host)
	return host


func _status_code(result: Dictionary) -> int:
	return result["status"]["code"]


func _status_message(result: Dictionary) -> String:
	return result["status"]["message"]


func _start(host: ScholaTrainingHost, autoreset_mode := AUTORESET_DISABLED) -> Dictionary:
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)
	assert_int(_status_code(host.set_autoreset_mode(autoreset_mode))).is_equal(STATUS_OK)
	return host.define()


func test_empty_scene_returns_actionable_status() -> void:
	var root := _test_root()
	var host := _add_host(root)

	var result := host.initialize_session()

	assert_int(_status_code(result)).is_equal(STATUS_NOT_FOUND)
	assert_str(_status_message(result)).contains("US4TestRoot")
	assert_str(_status_message(result)).contains("add at least one trainable environment")


func test_invalid_environment_names_node_and_public_diagnostic() -> void:
	var root := _test_root()
	var environment := TestEnvironment.new() as ScholaEnvironment
	environment.name = "BrokenEnvironment"
	root.add_child(environment)
	var host := _add_host(root)

	var result := host.initialize_session()

	assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
	assert_str(_status_message(result)).contains("BrokenEnvironment")
	assert_str(_status_message(result)).contains("Add a ScholaAgent node")


func test_discovery_order_becomes_stable_environment_ids() -> void:
	var root := _test_root()
	_add_environment(root, "FirstEnvironment", "first_agent")
	_add_environment(root, "SecondEnvironment", "second_agent")
	var host := _add_host(root)

	var definition := _start(host)
	var environments: Array = definition["value"]["environments"]
	assert_int(environments.size()).is_equal(2)
	assert_array(environments[0]["agents"].keys()).contains_exactly(["first_agent"])
	assert_array(environments[1]["agents"].keys()).contains_exactly(["second_agent"])

	var reset := host.reset({})
	assert_int(_status_code(reset)).is_equal(STATUS_OK)
	assert_array(reset["value"].keys()).contains_exactly([0, 1])


func test_duplicate_initialization_and_operations_before_initialization_fail() -> void:
	var root := _test_root()
	_add_environment(root, "Environment", "agent")
	var host := _add_host(root)

	assert_int(_status_code(host.define())).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.step({"actions": []}))).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_FAILED_PRECONDITION)


func test_freed_environment_fails_and_closes_session() -> void:
	var root := _test_root()
	var environment := _add_environment(root, "FreedEnvironment", "agent")
	var host := _add_host(root)
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)
	environment.free()

	var result := host.set_autoreset_mode(AUTORESET_DISABLED)

	assert_int(_status_code(result)).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(_status_message(result)).contains("was freed")
	assert_int(_status_code(host.define())).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)


func test_close_is_idempotent_and_rejects_later_work() -> void:
	var root := _test_root()
	_add_environment(root, "Environment", "agent")
	var host := _add_host(root)
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)

	assert_int(_status_code(host.close())).is_equal(STATUS_OK)
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)


func test_partial_definition_failure_does_not_leave_a_usable_session() -> void:
	var root := _test_root()
	_add_environment(root, "FirstEnvironment", "first_agent")
	var invalid := _add_environment(root, "InvalidEnvironment", "duplicate")
	_add_agent(invalid, "SecondDuplicate", "duplicate")
	var host := _add_host(root)
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)
	assert_int(_status_code(host.set_autoreset_mode(AUTORESET_DISABLED))).is_equal(STATUS_OK)

	var result := host.define()

	assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
	assert_object(result["value"]).is_null()
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)


func test_multiple_environments_run_repeated_episodes_without_state_leakage() -> void:
	var root := _test_root()
	var first := _add_environment(root, "FirstEnvironment", "first_agent") as TestEnvironment
	var second := _add_environment(root, "SecondEnvironment", "second_agent") as TestEnvironment
	var host := _add_host(root)
	assert_int(_status_code(_start(host, AUTORESET_SAME_STEP))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)

	var actions := {"actions": [{"first_agent": 1}, {"second_agent": 2}]}
	var first_step := host.step(actions)
	assert_int(_status_code(first_step)).is_equal(STATUS_OK)
	assert_float(first_step["value"]["state"][0]["first_agent"]["reward"]).is_equal(1.0)
	assert_int(first.reset_count).is_equal(1)
	assert_int(second.reset_count).is_equal(1)

	var terminal_step := host.step(actions)
	assert_int(_status_code(terminal_step)).is_equal(STATUS_OK)
	assert_array(terminal_step["value"]["initial_state"].keys()).contains_exactly([0, 1])
	assert_int(first.reset_count).is_equal(2)
	assert_int(second.reset_count).is_equal(2)

	var next_episode_step := host.step(actions)
	assert_int(_status_code(next_episode_step)).is_equal(STATUS_OK)
	assert_bool(next_episode_step["value"]["state"][0]["first_agent"]["terminated"]).is_false()
	assert_int(first.reset_count).is_equal(2)
	assert_int(second.reset_count).is_equal(2)


func test_next_step_autoreset_consumes_the_following_step() -> void:
	var root := _test_root()
	var environment := _add_environment(root, "Environment", "agent") as TestEnvironment
	environment.episode_length = 1
	var host := _add_host(root)
	assert_int(_status_code(_start(host, AUTORESET_NEXT_STEP))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	var actions := {"actions": [{"agent": 2}]}

	var terminal := host.step(actions)
	assert_bool(terminal["value"]["state"][0]["agent"]["terminated"]).is_true()
	var autoreset := host.step(actions)

	assert_int(_status_code(autoreset)).is_equal(STATUS_OK)
	assert_bool(autoreset["value"]["state"][0]["agent"]["terminated"]).is_false()
	assert_float(autoreset["value"]["state"][0]["agent"]["reward"]).is_equal(0.0)
	assert_int(environment.reset_count).is_equal(2)


func test_disabled_autoreset_preserves_terminal_state() -> void:
	var root := _test_root()
	var environment := _add_environment(root, "Environment", "agent") as TestEnvironment
	environment.episode_length = 1
	var host := _add_host(root)
	assert_int(_status_code(_start(host, AUTORESET_DISABLED))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	var actions := {"actions": [{"agent": 1}]}

	var terminal := host.step(actions)
	var retained := host.step(actions)

	assert_int(_status_code(retained)).is_equal(STATUS_OK)
	assert_bool(terminal["value"]["state"][0]["agent"]["terminated"]).is_true()
	assert_bool(retained["value"]["state"][0]["agent"]["terminated"]).is_true()
	assert_int(environment.reset_count).is_equal(1)
