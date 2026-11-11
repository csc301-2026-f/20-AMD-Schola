# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

class_name TrainingHostIntegrationTest
extends GdUnitTestSuite

const TestAgent := preload("res://tests/integration/support/us4_test_agent.gd")
const TestEnvironment := preload("res://tests/integration/support/us4_test_environment.gd")

const STATUS_OK := 0
const STATUS_INVALID_ARGUMENT := 1
const STATUS_NOT_FOUND := 2
const STATUS_INVALID_DATA := 3
const STATUS_FAILED_PRECONDITION := 5

const AUTORESET_SAME_STEP := 0
const AUTORESET_NEXT_STEP := 1
const AUTORESET_DISABLED := 2

var _previous_scene: Node


func before_test() -> void:
	_previous_scene = get_tree().current_scene


func after_test() -> void:
	get_tree().current_scene = _previous_scene


func _test_root() -> Node:
	var root := auto_free(Node.new()) as Node
	root.name = "US4TestRoot"
	get_tree().root.add_child(root)
	get_tree().current_scene = root
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


func _add_agent(environment: Node, node_name: String, agent_id: String) -> ScholaAgent:
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


func test_invalid_action_error_identifies_the_agent() -> void:
	for invalid_action in [99, "bad"]:
		var root := _test_root()
		var environment := _add_environment(root, "Environment", "first")
		var second = _add_agent(environment, "Second", "second")
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		var result := host.step({"actions": [{"first": 1, "second": invalid_action}]})
		assert_int(_status_code(result)).is_equal(STATUS_INVALID_ARGUMENT)
		assert_str(_status_message(result)).contains("Agent 'second': rejected action:")
		assert_object(environment.get_node("first").last_action).is_null()
		assert_object(second.last_action).is_null()


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
	assert_str(environments[0]["agents"]["first_agent"]["action_space"]["type"]).is_equal("Discrete")

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


func test_duplicate_ids_fail_during_session_initialization() -> void:
	var root := _test_root()
	_add_environment(root, "FirstEnvironment", "first_agent")
	var invalid := _add_environment(root, "InvalidEnvironment", "duplicate")
	_add_agent(invalid, "SecondDuplicate", "duplicate")
	var host := _add_host(root)

	var result := host.initialize_session()

	assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
	assert_str(_status_message(result)).contains("InvalidEnvironment")
	assert_str(_status_message(result)).contains("Duplicate agent ID")
	assert_object(result["value"]).is_null()
	assert_int(_status_code(host.define())).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)


func test_partial_definition_failure_does_not_leave_a_usable_session() -> void:
	var root := _test_root()
	_add_environment(root, "FirstEnvironment", "first_agent")
	var invalid := _add_environment(root, "InvalidEnvironment", "duplicate")
	var host := _add_host(root)
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)
	assert_int(_status_code(host.set_autoreset_mode(AUTORESET_DISABLED))).is_equal(STATUS_OK)
	# Introduce the conflict after preflight to exercise cleanup during define().
	_add_agent(invalid, "SecondDuplicate", "duplicate")

	var result := host.define()

	assert_int(_status_code(result)).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(_status_message(result)).contains("duplicate")
	assert_object(result["value"]).is_null()
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)


func test_invalid_reset_requests_do_not_reset_any_environment() -> void:
	var root := _test_root()
	var first := _add_environment(root, "FirstEnvironment", "first") as TestEnvironment
	var second := _add_environment(root, "SecondEnvironment", "second") as TestEnvironment
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	var invalid_requests: Array[Dictionary] = [
		{"0": {}}, {0.5: {}}, {true: {}}, {4294967296: {}}, {-1: {}}, {2: {}},
		{0: "invalid settings"}, {0: {}, 1: {"seed": "42"}},
		{0: {"seed": 1.5}}, {0: {"seed": null}},
		{0: {"seed": 2147483648}}, {0: {"seed": -2147483649}},
		{0: {"options": "invalid options"}},
		{0: {"options": {1: "value"}}}, {0: {"options": {"key": 1}}},
	]
	for request in invalid_requests:
		var result := host.reset(request)
		assert_int(_status_code(result)).is_equal(STATUS_INVALID_ARGUMENT)
		assert_object(result["value"]).is_null()
		assert_int(first.reset_count).is_equal(0)
		assert_int(second.reset_count).is_equal(0)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	assert_int(first.reset_count).is_equal(1)
	assert_int(second.reset_count).is_equal(1)


func test_reset_forwards_seed_boundaries_and_options() -> void:
	var root := _test_root()
	var environment := _add_environment(root, "Environment", "agent") as TestEnvironment
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	for seed in [-2147483648, 2147483647]:
		var result := host.reset({0: {"seed": seed, "options": {"track": "hard"}}})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		assert_int(environment.last_seed).is_equal(seed)
		assert_dict(environment.last_options).is_equal({"track": "hard"})
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	assert_object(environment.last_seed).is_null()
	assert_dict(environment.last_options).is_empty()


func test_multiple_environments_run_repeated_episodes_without_state_leakage() -> void:
	var root := _test_root()
	var first := _add_environment(root, "FirstEnvironment", "first_agent") as TestEnvironment
	var second := _add_environment(root, "SecondEnvironment", "second_agent") as TestEnvironment
	var host := _add_host(root)
	assert_int(_status_code(_start(host, AUTORESET_SAME_STEP))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)

	var actions := {"actions": [{"first_agent": 1}, {"second_agent": 2}]}
	var first_step := host.step(actions)
	assert_int(_status_code(first_step)).override_failure_message(_status_message(first_step)).is_equal(STATUS_OK)
	if _status_code(first_step) != STATUS_OK:
		return
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


func _dynamic_environment(root: Node) -> ScholaEnvironment:
	var environment = load("res://tests/integration/support/us4_dynamic_environment.gd").new()
	var templates := auto_free(Node.new()) as Node
	for id in ["a", "b", "c"]:
		environment.definitions.append(_add_agent(templates, id, id))
	_add_agent(environment, "a", "a")
	root.add_child(environment)
	environment.episode_length = 100
	return environment


func test_agent_can_spawn_a_copy_and_die_in_the_same_step() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	var original = environment.get_agents()[0]
	original.on_action = func():
		_add_agent(environment, "b", "b")
		original.queue_free()
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	var initial := host.reset({})
	assert_array(initial["value"][0].keys()).contains_exactly(["a"])
	var result := host.step({"actions": [{"a": 1}]})
	assert_int(_status_code(result)).is_equal(STATUS_OK)
	var agents: Dictionary = result["value"]["state"][0]
	assert_bool(agents["a"]["terminated"]).is_true()
	assert_bool(agents["b"]["terminated"]).is_false()
	assert_float(agents["b"]["reward"]).is_equal(0.0)
	assert_int(_status_code(host.step({"actions": [{"b": 2}]}))).is_equal(STATUS_OK)


func test_replacing_an_active_node_with_the_same_id_is_rejected() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	environment.get_agents()[0].free()
	var replacement = _add_agent(environment, "a", "a")
	var result := host.step({"actions": [{"a": 1}]})
	assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
	assert_str(_status_message(result)).contains("replaced before reset")
	assert_object(replacement.last_action).is_null()
	assert_object(result["value"]).is_null()


func test_departure_during_observation_returns_a_terminal_transition() -> void:
	for queued in [false, true]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var original = environment.get_agents()[0]
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		original.on_observe = func():
			if queued:
				original.queue_free()
			else:
				environment.remove_child(original)
		var result := host.step({"actions": [{"a": 2}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		var state: Dictionary = result["value"]["state"][0]["a"]
		assert_bool(state["terminated"]).is_true()
		assert_float(state["reward"]).is_equal(0.0)
		assert_int(state["observation"]).is_equal(0)
		if not queued:
			original.free()


func test_detached_templates_have_safe_configuration_diagnostics() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	assert_array(environment.get_configuration_errors()).is_empty()
	# Duplicate IDs exercise the diagnostic label for detached templates.
	environment.definitions[1].agent_id = "a"
	var errors := environment.get_configuration_errors()
	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0]).contains("Duplicate agent ID 'a'")
	assert_str(errors[0]).contains("instance")


func test_queued_ancestor_removes_agents_in_every_step_callback() -> void:
	for phase in ["action", "observe", "result"]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var container := Node.new()
		var nested := Node.new()
		environment.add_child(container)
		container.add_child(nested)
		var first = environment.get_agents()[0]
		first.reparent(nested)
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		match phase:
			"action":
				first.on_action = func(): container.queue_free()
			"observe":
				first.on_observe = func(): container.queue_free()
			"result":
				environment.on_step_result = func(_agent): container.queue_free()
		var result := host.step({"actions": [{"a": 2}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		var state: Dictionary = result["value"]["state"][0]["a"]
		assert_bool(state["terminated"]).is_true()
		assert_float(state["reward"]).is_equal(0.0)
		assert_int(state["observation"]).is_equal(0)


func test_reset_can_replace_queued_containers_with_the_same_agent_ids() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	var container := Node.new()
	var nested := Node.new()
	environment.add_child(container)
	container.add_child(nested)
	environment.get_agents()[0].reparent(nested)
	_add_agent(nested, "b", "b")
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	environment.on_reset = func():
		for child in environment.get_children():
			child.queue_free()
		var replacement := Node.new()
		var replacement_nested := Node.new()
		environment.add_child(replacement)
		replacement.add_child(replacement_nested)
		_add_agent(replacement_nested, "a", "a")
		_add_agent(replacement_nested, "b", "b")
	for iteration in range(2):
		var initial := host.reset({})
		assert_int(_status_code(initial)).is_equal(STATUS_OK)
		assert_array(initial["value"][0].keys()).contains_exactly(["a", "b"])
		var result := host.step({"actions": [{"a": 1, "b": 2}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		assert_int(result["value"]["state"][0]["a"]["observation"]).is_equal(1)
		assert_int(result["value"]["state"][0]["b"]["observation"]).is_equal(2)


func test_later_callbacks_reconcile_already_observed_departures() -> void:
	for from_result in [false, true]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var first = environment.get_agents()[0]
		var second = _add_agent(environment, "b", "b")
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		if from_result:
			environment.on_step_result = func(agent):
				if agent == first:
					first.queue_free()
		else:
			second.on_observe = func(): first.queue_free()
		var result := host.step({"actions": [{"a": 2, "b": 1}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		var agents: Dictionary = result["value"]["state"][0]
		assert_bool(agents["a"]["terminated"]).is_true()
		assert_float(agents["a"]["reward"]).is_equal(0.0)
		assert_int(agents["a"]["observation"]).is_equal(0)
		assert_bool(agents["b"]["terminated"]).is_false()
		environment.on_step_result = Callable()
		second.on_observe = Callable()
		assert_int(_status_code(host.step({"actions": [{"b": 1}]}))).is_equal(STATUS_OK)


func test_callback_births_participate_before_episode_completion() -> void:
	for from_result in [false, true]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var first = environment.get_agents()[0]
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		environment.episode_length = 1
		var spawn := func():
			var second = _add_agent(environment, "b", "b")
			# A birth observation can itself spawn another declared agent.
			second.on_observe = func():
				second.on_observe = Callable()
				_add_agent(environment, "c", "c")
		if from_result:
			environment.on_step_result = func(_agent): spawn.call()
		else:
			first.on_observe = spawn
		var result := host.step({"actions": [{"a": 2}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		var agents: Dictionary = result["value"]["state"][0]
		assert_array(agents.keys()).contains_exactly(["a", "b", "c"])
		assert_bool(agents["a"]["terminated"]).is_true()
		for id in ["b", "c"]:
			assert_bool(agents[id]["terminated"]).is_false()
			assert_float(agents[id]["reward"]).is_equal(0.0)
			assert_int(agents[id]["observation"]).is_equal(0)
			assert_object(environment.get_node(id).last_action).is_null()
		environment.on_step_result = Callable()
		environment.episode_length = 100
		var following := host.step({"actions": [{"b": 1, "c": 2}]})
		assert_int(_status_code(following)).is_equal(STATUS_OK)
		assert_int(following["value"]["state"][0]["b"]["observation"]).is_equal(1)
		assert_int(following["value"]["state"][0]["c"]["observation"]).is_equal(2)


func test_removed_agent_gets_final_transition_and_reset_rebinds_new_nodes() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	_add_agent(environment, "b", "b")
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	environment.get_agents()[0].free()
	var result := host.step({"actions": [{"a": 1, "b": 2}]})
	assert_int(_status_code(result)).is_equal(STATUS_OK)
	assert_bool(result["value"]["state"][0]["a"]["terminated"]).is_true()
	assert_int(_status_code(host.step({"actions": [{"b": 1}]}))).is_equal(STATUS_OK)
	for agent in environment.get_agents():
		agent.free()
	_add_agent(environment, "a", "a")
	var initial := host.reset({})
	assert_int(_status_code(initial)).is_equal(STATUS_OK)
	assert_array(initial["value"][0].keys()).contains_exactly(["a"])
	assert_int(_status_code(host.step({"actions": [{"a": 2}]}))).is_equal(STATUS_OK)


func test_spawned_agent_must_match_declared_id_and_spaces() -> void:
	for invalid_id in [false, true]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		var spawned := _add_agent(environment, "spawned", "unknown" if invalid_id else "b")
		if not invalid_id:
			var incompatible := ScholaDiscreteSpace.new()
			incompatible.n = 5
			spawned.action_space = incompatible
		var result := host.step({"actions": [{"a": 1}]})
		assert_int(_status_code(result)).is_not_equal(STATUS_OK)
		assert_object(result["value"]).is_null()


func test_empty_initial_population_can_discover_a_later_birth() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	environment.get_agents()[0].free()
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	var initial := host.reset({})
	assert_int(_status_code(initial)).is_equal(STATUS_OK)
	assert_dict(initial["value"][0]).is_empty()
	for iteration in range(3):
		var empty_step := host.step({"actions": [{}]})
		assert_int(_status_code(empty_step)).is_equal(STATUS_OK)
		assert_dict(empty_step["value"]["state"][0]).is_empty()
	assert_int(environment.reset_count).is_equal(1)
	_add_agent(environment, "c", "c")
	var result := host.step({"actions": [{}]})
	assert_int(_status_code(result)).is_equal(STATUS_OK)
	assert_array(result["value"]["state"][0].keys()).contains_exactly(["c"])
	assert_int(_status_code(host.step({"actions": [{"c": 1}]}))).is_equal(STATUS_OK)


func test_dynamic_population_completion_obeys_all_autoreset_modes() -> void:
	for mode in [AUTORESET_DISABLED, AUTORESET_SAME_STEP, AUTORESET_NEXT_STEP]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var original = environment.get_agents()[0]
		original.on_action = func():
			_add_agent(environment, "b", "b")
			original.queue_free()
		var host := _add_host(root)
		assert_int(_status_code(_start(host, mode))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		assert_int(_status_code(host.step({"actions": [{"a": 1}]}))).is_equal(STATUS_OK)
		environment.episode_length = 1
		var terminal := host.step({"actions": [{"b": 2}]})
		assert_int(_status_code(terminal)).is_equal(STATUS_OK)
		assert_bool(terminal["value"]["state"][0]["b"]["terminated"]).is_true()
		if mode == AUTORESET_SAME_STEP:
			assert_array(terminal["value"]["initial_state"][0].keys()).contains_exactly(["b"])
		else:
			var following := host.step({"actions": [{}]})
			assert_int(_status_code(following)).is_equal(STATUS_OK)
			if mode == AUTORESET_NEXT_STEP:
				assert_array(following["value"]["state"][0].keys()).contains_exactly(["b"])
				assert_bool(following["value"]["state"][0]["b"]["terminated"]).is_false()
			else:
				assert_bool(following["value"]["state"][0]["b"]["terminated"]).is_true()
