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
const STATUS_CLOSED := 7

const AUTORESET_SAME_STEP := 0
const AUTORESET_NEXT_STEP := 1
const AUTORESET_DISABLED := 2


class StepCountEnvironment extends TestEnvironment:
	var reset_steps: Array[int] = []

	func _reset_episode(seed: Variant, options: Dictionary) -> void:
		reset_steps.append(get_episode_step())
		super._reset_episode(seed, options)


class StepCountAgent extends TestAgent:
	func _observe() -> Variant:
		return get_parent().get_episode_step()


class ConfigurationCallbackEnvironment extends TestEnvironment:
	var on_configuration: Callable

	func _get_possible_agents() -> Array[ScholaAgent]:
		if on_configuration.is_valid():
			on_configuration.call()
		return get_agents()


class TemplateEnvironment extends TestEnvironment:
	var templates: Array[ScholaAgent] = []

	func _get_possible_agents() -> Array[ScholaAgent]:
		return templates


class FreeingEnvironment extends TestEnvironment:
	var victim: Node

	func _reset_episode(seed: Variant, options: Dictionary) -> void:
		super._reset_episode(seed, options)
		_free_victim()

	func _get_step_result(agent: ScholaAgent) -> Dictionary:
		_free_victim()
		return super._get_step_result(agent)

	func _free_victim() -> void:
		if is_instance_valid(victim):
			victim.free()


class HostCallbackEnvironment extends TestEnvironment:
	var on_callback: Callable

	func _reset_episode(seed: Variant, options: Dictionary) -> void:
		super._reset_episode(seed, options)
		_call_back()

	func _get_step_result(agent: ScholaAgent) -> Dictionary:
		_call_back()
		return super._get_step_result(agent)

	func _call_back() -> void:
		if on_callback.is_valid():
			on_callback.call()

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


func _add_stacker(agent: ScholaAgent) -> void:
	var stacker := ScholaStacker.new()
	stacker.output_kind = 1 # Dict: Point_0 is the newest observation.
	stacker.stack_size = 3
	agent.observation_adapters = [stacker]


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


func test_reset_callbacks_and_initial_observations_see_zero_completed_steps(
	autoreset_mode: int,
	_test_parameters := [[AUTORESET_DISABLED], [AUTORESET_SAME_STEP], [AUTORESET_NEXT_STEP]]
) -> void:
	var root := _test_root()
	var environment := StepCountEnvironment.new()
	var agent := StepCountAgent.new()
	agent.agent_id = "clock"
	agent.observation_space = _space()
	agent.action_space = _space()
	environment.add_child(agent)
	root.add_child(environment)
	var host := _add_host(root)
	assert_int(_status_code(_start(host, autoreset_mode))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	var action := {"actions": [{"clock": 0}]}
	assert_int(_status_code(host.step(action))).is_equal(STATUS_OK)
	var terminal := host.step(action)
	assert_int(_status_code(terminal)).is_equal(STATUS_OK)

	var observation: Variant
	if autoreset_mode == AUTORESET_DISABLED:
		var reset := host.reset({})
		assert_int(_status_code(reset)).is_equal(STATUS_OK)
		observation = reset.value[0]["clock"].observation
	elif autoreset_mode == AUTORESET_SAME_STEP:
		observation = terminal.value.initial_state[0]["clock"].observation
	else:
		var reset_step := host.step(action)
		assert_int(_status_code(reset_step)).is_equal(STATUS_OK)
		observation = reset_step.value.state[0]["clock"].observation

	assert_array(environment.reset_steps).contains_exactly([0, 0])
	assert_int(observation).is_equal(0)
	assert_int(environment.get_episode_step()).is_equal(0)


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


func test_nested_environments_are_rejected_through_grouping_nodes() -> void:
	for grouped in [false, true]:
		var root := _test_root()
		var outer := _add_environment(root, "OuterEnvironment", "outer")
		var container: Node = outer
		if grouped:
			container = Node.new()
			outer.add_child(container)
		var inner := _add_environment(container, "InnerEnvironment", "inner")
		assert_str("; ".join(inner.get_configuration_errors())).contains("Nested ScholaEnvironment nodes are unsupported")
		var host := _add_host(root)
		var result := host.initialize_session()
		assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
		assert_str(_status_message(result)).contains("InnerEnvironment")
		assert_str(_status_message(result)).contains("Nested ScholaEnvironment nodes are unsupported")


func test_nesting_during_a_session_is_rejected_before_publishing_results() -> void:
	for phase in ["define", "reset", "step", "reset_callback", "step_callback"]:
		var root := _test_root()
		var first := _add_environment(root, "First", "first")
		var second := _add_environment(root, "Second", "second")
		var host := _add_host(root)
		assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)
		assert_int(_status_code(host.set_autoreset_mode(AUTORESET_DISABLED))).is_equal(STATUS_OK)
		var result: Dictionary
		if phase == "define":
			second.reparent(first)
			result = host.define()
		else:
			assert_int(_status_code(host.define())).is_equal(STATUS_OK)
			if phase == "reset_callback":
				second.on_reset = func(): first.reparent(second)
				result = host.reset({})
			elif phase == "reset":
				second.reparent(first)
				result = host.reset({})
			else:
				assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
				if phase == "step_callback":
					second.get_agents()[0].on_action = func(): first.reparent(second)
				else:
					second.reparent(first)
				result = host.step({"actions": [{"first": 1}, {"second": 1}]})
		assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
		assert_str(_status_message(result)).contains("Nested ScholaEnvironment nodes are unsupported")
		assert_object(result["value"]).is_null()
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)


func test_callbacks_cannot_introduce_unregistered_nested_environments() -> void:
	for phase in ["reset", "action", "observe", "result"]:
		var root := _test_root()
		var environment := _add_environment(root, "Environment", "agent")
		var agent = environment.get_agents()[0]
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		var introduce_nested := func():
			var grouping := Node.new()
			environment.add_child(grouping)
			_add_environment(grouping, "NewNestedEnvironment", "nested_agent")
		var result: Dictionary
		if phase == "reset":
			environment.on_reset = introduce_nested
			result = host.reset({})
		else:
			assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
			match phase:
				"action": agent.on_action = introduce_nested
				"observe": agent.on_observe = introduce_nested
				"result": environment.on_step_result = func(_agent): introduce_nested.call()
			result = host.step({"actions": [{"agent": 1}]})
		assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
		assert_str(_status_message(result)).contains("NewNestedEnvironment")
		assert_str(_status_message(result)).contains("Nested ScholaEnvironment nodes are unsupported")
		assert_object(result["value"]).is_null()
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)


func test_status_message_keeps_non_ascii_node_names() -> void:
	var root := _test_root()
	var environment := TestEnvironment.new() as ScholaEnvironment
	environment.name = "环境Ünïcode"
	root.add_child(environment)
	var host := _add_host(root)

	var result := host.initialize_session()

	assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
	assert_str(_status_message(result)).contains("环境Ünïcode")


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
	assert_bool(host.is_session_active()).is_true()
	environment.free()

	var result := host.set_autoreset_mode(AUTORESET_DISABLED)

	assert_int(_status_code(result)).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(_status_message(result)).contains("was freed")
	assert_bool(host.is_session_active()).is_false()
	assert_int(_status_code(host.define())).is_equal(STATUS_FAILED_PRECONDITION)
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)


func test_possible_agents_callback_can_free_another_environment_safely() -> void:
	for remove_earlier in [false, true]:
		var root := _test_root()
		var callback_environment := ConfigurationCallbackEnvironment.new()
		_add_agent(callback_environment, "callback_agent", "callback_agent")
		root.add_child(callback_environment)
		var victim := _add_environment(root, "Victim", "victim")
		if remove_earlier:
			root.move_child(victim, 0)
		callback_environment.on_configuration = victim.free
		var host := _add_host(root)

		var result := host.initialize_session()

		assert_int(_status_code(result)).is_equal(STATUS_FAILED_PRECONDITION)
		assert_str(_status_message(result)).contains("environment %d was freed" % (0 if remove_earlier else 1))
		assert_bool(host.is_session_active()).is_false()


func test_configuration_rejects_environments_outside_the_scene_or_queued_via_parent() -> void:
	for mutation in ["reparent", "queue_parent"]:
		for mutate_earlier in [false, true]:
			var root := _test_root()
			var callback_environment := ConfigurationCallbackEnvironment.new()
			_add_agent(callback_environment, "callback_agent", "callback_agent")
			root.add_child(callback_environment)
			var container := Node.new()
			root.add_child(container)
			var victim := _add_environment(container, "Victim", "victim")
			if mutate_earlier:
				root.move_child(container, 0)
			if mutation == "reparent":
				callback_environment.on_configuration = func(): victim.reparent(get_tree().root)
			else:
				callback_environment.on_configuration = container.queue_free
			var host := _add_host(root)

			var result := host.initialize_session()

			var expected_index := 0 if mutate_earlier else 1
			assert_int(_status_code(result)).is_equal(STATUS_FAILED_PRECONDITION)
			assert_str(_status_message(result)).contains("environment %d" % expected_index)
			if mutation == "reparent":
				assert_str(_status_message(result)).contains("outside the current scene")
				victim.free()
			else:
				assert_str(_status_message(result)).contains("ancestor").contains("queued for deletion")
			assert_bool(host.is_session_active()).is_false()


func test_environment_freed_by_another_environment_closes_session(
	during_reset: bool,
	_test_parameters := [[true], [false]]
) -> void:
	var root := _test_root()
	var first := FreeingEnvironment.new()
	first.name = "FirstEnvironment"
	_add_agent(first, "first_agent", "first_agent")
	root.add_child(first)
	var second := _add_environment(root, "SecondEnvironment", "second_agent")
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	if not during_reset:
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	first.victim = second

	var actions := {"actions": [{"first_agent": 1}, {"second_agent": 1}]}
	var result: Dictionary = host.reset({}) if during_reset else host.step(actions)

	assert_int(_status_code(result)).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(_status_message(result)).contains("environment 1 was freed")
	assert_object(result["value"]).is_null()
	assert_bool(host.is_session_active()).is_false()


func test_callbacks_cannot_reenter_the_host_and_close_waits_for_the_call(
	during_reset: bool,
	_test_parameters := [[true], [false]]
) -> void:
	var root := _test_root()
	var environment := HostCallbackEnvironment.new()
	environment.name = "Environment"
	_add_agent(environment, "agent", "agent")
	root.add_child(environment)
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	if not during_reset:
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	var nested: Array[int] = []
	environment.on_callback = func() -> void:
		nested.append(_status_code(host.step({"actions": [{"agent": 1}]})))
		nested.append(_status_code(host.close()))

	var result: Dictionary = host.reset({}) if during_reset else host.step({"actions": [{"agent": 1}]})

	# The nested step is refused, and the close happens once the outer call returns
	assert_array(nested).contains_exactly([STATUS_FAILED_PRECONDITION, STATUS_OK])
	assert_int(_status_code(result)).is_equal(STATUS_CLOSED)
	assert_object(result["value"]).is_null()
	assert_bool(host.is_session_active()).is_false()


func test_close_is_idempotent_and_rejects_later_work() -> void:
	var root := _test_root()
	_add_environment(root, "Environment", "agent")
	var host := _add_host(root)
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)

	assert_int(_status_code(host.close())).is_equal(STATUS_OK)
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_FAILED_PRECONDITION)


func test_an_empty_possible_agent_slot_fails_session_initialization() -> void:
	var root := _test_root()
	var environment := TemplateEnvironment.new()
	environment.name = "Environment"
	var agent := _add_agent(environment, "agent", "agent")
	# The second slot was meant for another agent but never assigned
	environment.templates = [agent, null]
	root.add_child(environment)
	var host := _add_host(root)

	var result := host.initialize_session()

	assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
	assert_str(_status_message(result)).contains("Possible agent 1 is empty")
	environment.templates = [agent]
	assert_int(_status_code(host.initialize_session())).is_equal(STATUS_OK)


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


func test_missing_action_in_later_environment_prevents_all_actions() -> void:
	var root := _test_root()
	var first := _add_environment(root, "FirstEnvironment", "first")
	_add_environment(root, "SecondEnvironment", "second")
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)

	var result := host.step({"actions": [{"first": 1}, {}]})

	assert_int(_status_code(result)).is_equal(STATUS_INVALID_ARGUMENT)
	assert_str(_status_message(result)).contains("environment 1: missing action for unfinished agent second")
	assert_object(result["value"]).is_null()
	assert_bool(first.get_node("first").last_action == null).is_true()
	assert_bool(host.is_session_active()).is_false()


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


func test_reset_discovers_births_from_initial_observation_callbacks() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	var first = environment.get_agents()[0]
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	first.on_observe = func():
		first.on_observe = Callable()
		var second = _add_agent(environment, "b", "b")
		second.on_observe = func():
			second.on_observe = Callable()
			_add_agent(environment, "c", "c")
	var initial := host.reset({})
	assert_int(_status_code(initial)).is_equal(STATUS_OK)
	assert_array(initial["value"][0].keys()).contains_exactly(["a", "b", "c"])
	assert_int(_status_code(host.step({"actions": [{"a": 1, "b": 1, "c": 1}]}))).is_equal(STATUS_OK)


func test_reset_skips_pending_agents_removed_by_an_observation() -> void:
	for removal in ["free", "queue", "container"]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var first = environment.get_agents()[0]
		var container := Node.new()
		environment.add_child(container)
		var second = _add_agent(container, "b", "b")
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		first.on_observe = func():
			first.on_observe = Callable()
			match removal:
				"free": second.free()
				"queue": second.queue_free()
				"container": container.queue_free()
		var initial := host.reset({})
		assert_int(_status_code(initial)).is_equal(STATUS_OK)
		assert_array(initial["value"][0].keys()).contains_exactly(["a"])
		assert_int(_status_code(host.step({"actions": [{"a": 1}]}))).is_equal(STATUS_OK)


func test_reset_reconciles_departures_after_later_observations() -> void:
	for removal in ["free", "detach", "container"]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var first = environment.get_agents()[0]
		var container := Node.new()
		environment.add_child(container)
		first.reparent(container)
		var second = _add_agent(environment, "b", "b")
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		second.on_observe = func():
			second.on_observe = Callable()
			match removal:
				"free": first.free()
				"detach": container.remove_child(first)
				"container": container.queue_free()
		var initial := host.reset({})
		assert_int(_status_code(initial)).is_equal(STATUS_OK)
		assert_array(initial["value"][0].keys()).contains_exactly(["b"])
		assert_int(_status_code(host.step({"actions": [{"b": 1}]}))).is_equal(STATUS_OK)
		if removal == "detach":
			first.free()


func test_temporary_detachment_during_observation_uses_final_membership() -> void:
	for phase in ["reset", "step"]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var first = environment.get_agents()[0]
		var second = _add_agent(environment, "b", "b")
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		if phase == "step":
			assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		first.on_observe = func():
			first.on_observe = Callable()
			environment.remove_child(first)
		second.on_observe = func():
			second.on_observe = Callable()
			environment.add_child(first)
		var result: Dictionary
		if phase == "reset":
			result = host.reset({})
			assert_int(_status_code(result)).is_equal(STATUS_OK)
			assert_array(result["value"][0].keys()).contains_exactly(["a", "b"])
		else:
			result = host.step({"actions": [{"a": 1, "b": 2}]})
			assert_int(_status_code(result)).is_equal(STATUS_OK)
			var agents: Dictionary = result["value"]["state"][0]
			assert_bool(agents["a"]["terminated"]).is_false()
			assert_float(agents["a"]["reward"]).is_equal(1.0)
			assert_int(agents["a"]["observation"]).is_equal(1)
		var following := host.step({"actions": [{"a": 2, "b": 1}]})
		assert_int(_status_code(following)).is_equal(STATUS_OK)
		assert_bool(following["value"]["state"][0]["a"]["terminated"]).is_false()


func test_identity_changes_before_action_dispatch_reject_stale_actions() -> void:
	for fallback_id in [false, true]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var first = environment.get_agents()[0]
		var second = _add_agent(environment, "b", "" if fallback_id else "b")
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		first.on_action = func():
			if fallback_id:
				second.name = "c"
			else:
				second.agent_id = "c"
		var result := host.step({"actions": [{"a": 1, "b": 2}]})
		assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
		assert_str(_status_message(result)).contains("Agent 'b'")
		assert_str(_status_message(result)).contains("agent ID changed before its action")
		assert_object(second.last_action).is_null()
		assert_int(second.observation).is_equal(0)
		assert_object(result["value"]).is_null()
		assert_int(_status_code(host.step({"actions": [{"a": 1, "c": 2}]}))).is_equal(STATUS_FAILED_PRECONDITION)


func test_published_agent_id_cannot_change_between_requests() -> void:
	for fallback_id in [false, true]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var agent = environment.get_agents()[0]
		if fallback_id:
			agent.agent_id = ""
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		if fallback_id:
			agent.name = "b"
		else:
			agent.agent_id = "b"

		var result := host.step({"actions": [{"a": 1}]})

		assert_int(_status_code(result)).is_equal(STATUS_INVALID_DATA)
		assert_str(_status_message(result)).contains("Agent 'a': agent ID changed after publication")
		assert_object(agent.last_action).is_null()
		assert_object(result["value"]).is_null()
		assert_bool(host.is_session_active()).is_false()


func test_skipped_actions_remain_terminal_after_same_step_reattachment() -> void:
	for phase in ["action", "observe", "result", "before_step", "pause_after_reattach"]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var first = environment.get_agents()[0]
		var second = _add_agent(environment, "b", "b")
		var third = _add_agent(environment, "c", "c")
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		var observed_ids: Array[String] = []
		var result_ids: Array[String] = []
		second.on_observe = func(): observed_ids.append("b")
		if phase == "before_step":
			environment.remove_child(second)
		else:
			first.on_action = func(): environment.remove_child(second)
		var reattach := func():
			environment.add_child(second)
			if phase == "pause_after_reattach":
				second.training_paused = true
		if phase in ["action", "before_step", "pause_after_reattach"]:
			third.on_action = reattach
		elif phase == "observe":
			third.on_observe = reattach
		environment.on_step_result = func(agent):
			result_ids.append(agent.agent_id)
			if phase == "result" and agent == third:
				reattach.call()

		var result := host.step({"actions": [{"a": 1, "b": 2, "c": 1}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		assert_object(second.get_parent()).is_same(environment)
		assert_object(second.last_action).is_null()
		assert_array(observed_ids).is_empty()
		assert_array(result_ids).contains_exactly(["a", "c"])
		var state: Dictionary = result["value"]["state"][0]["b"]
		assert_bool(state["terminated"]).is_true()
		assert_bool(state["truncated"]).is_false()
		assert_float(state["reward"]).is_equal(0.0)
		assert_int(state["observation"]).is_equal(0)
		first.on_action = Callable()
		third.on_action = Callable()
		third.on_observe = Callable()
		environment.on_step_result = Callable()
		assert_int(_status_code(host.step({"actions": [{"a": 1, "c": 2}]}))).is_equal(STATUS_OK)
		assert_object(second.last_action).is_null()
		second.training_paused = false
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		assert_int(_status_code(host.step({"actions": [{"a": 1, "b": 2, "c": 1}]}))).is_equal(STATUS_OK)
		assert_int(second.last_action).is_equal(2)


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
		assert_float(state["reward"]).is_equal(1.0 if phase == "result" else 0.0)
		assert_int(state["observation"]).is_equal(2 if phase == "result" else 0)


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
					return {"reward": 1.0, "truncated": true}
				return null
		else:
			second.on_observe = func(): first.queue_free()
		var result := host.step({"actions": [{"a": 2, "b": 1}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		var agents: Dictionary = result["value"]["state"][0]
		assert_bool(agents["a"]["terminated"]).is_equal(not from_result)
		assert_bool(agents["a"]["truncated"]).is_equal(from_result)
		assert_float(agents["a"]["reward"]).is_equal(1.0)
		assert_int(agents["a"]["observation"]).is_equal(2)
		assert_bool(agents["b"]["terminated"]).is_false()
		environment.on_step_result = Callable()
		second.on_observe = Callable()
		var replacement = _add_agent(environment, "Replacement", "a")
		assert_int(_status_code(host.step({"actions": [{"b": 1}]}))).is_equal(STATUS_OK)
		assert_object(replacement.last_action).is_null()
		var stale_action := host.step({"actions": [{"a": 1, "b": 1}]})
		assert_int(_status_code(stale_action)).is_equal(STATUS_FAILED_PRECONDITION)
		assert_str(_status_message(stale_action)).contains("Agent 'a': already finished this episode")


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


func test_training_pause_preserves_identity_and_resumes_without_an_action() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	var first = environment.get_agents()[0]
	var second = _add_agent(environment, "b", "b")
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	var callbacks: Array[String] = []
	second.on_observe = func(): callbacks.append("observe")
	second.on_action = func(): callbacks.append("act")
	first.on_action = func(): second.training_paused = true
	var paused := host.step({"actions": [{"a": 1, "b": 2}]})
	assert_int(_status_code(paused)).is_equal(STATUS_OK)
	assert_array(paused["value"]["state"][0].keys()).contains_exactly(["a"])
	assert_array(callbacks).contains_exactly(["act", "observe"])
	assert_int(second.last_action).is_equal(2)
	callbacks.clear()
	first.on_action = Callable()
	first.training_paused = true
	var all_paused := host.step({"actions": [{"a": 1}]})
	assert_int(_status_code(all_paused)).is_equal(STATUS_OK)
	assert_dict(all_paused["value"]["state"][0]).is_empty()
	for iteration in range(2):
		assert_int(_status_code(host.step({"actions": [{}]}))).is_equal(STATUS_OK)
	second.training_paused = false
	var resumed := host.step({"actions": [{}]})
	assert_int(_status_code(resumed)).is_equal(STATUS_OK)
	var state: Dictionary = resumed["value"]["state"][0]["b"]
	assert_bool(state["terminated"]).is_false()
	assert_float(state["reward"]).is_equal(1.0)
	assert_int(state["observation"]).is_equal(2)
	assert_array(callbacks).contains_exactly(["observe"])
	assert_int(_status_code(host.step({"actions": [{"b": 2}]}))).is_equal(STATUS_OK)
	assert_int(second.last_action).is_equal(2)


func test_paused_agents_prevent_completion_and_removal_still_terminates() -> void:
	for mode in [AUTORESET_DISABLED, AUTORESET_SAME_STEP, AUTORESET_NEXT_STEP]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		var second = _add_agent(environment, "b", "b")
		var host := _add_host(root)
		assert_int(_status_code(_start(host, mode))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		second.training_paused = true
		environment.on_step_result = func(agent): return {"reward": 1.0, "terminated": agent.agent_id == "a"}
		var result := host.step({"actions": [{"a": 1, "b": 2}]})
		assert_int(_status_code(result)).is_equal(STATUS_OK)
		assert_bool(result["value"]["state"][0]["a"]["terminated"]).is_true()
		assert_bool(result["value"]["state"][0].has("b")).is_false()
		assert_dict(result["value"]["initial_state"]).is_empty()
		assert_int(_status_code(host.step({"actions": [{}]}))).is_equal(STATUS_OK)
		assert_int(environment.reset_count).is_equal(1)
		second.free()
		var removed := host.step({"actions": [{}]})
		assert_int(_status_code(removed)).is_equal(STATUS_OK)
		assert_bool(removed["value"]["state"][0]["b"]["terminated"]).is_true()
		assert_float(removed["value"]["state"][0]["b"]["reward"]).is_equal(1.0)


func test_initially_paused_agents_are_observed_only_after_resuming() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	var second = _add_agent(environment, "b", "b")
	second.training_paused = true
	var callbacks: Array[String] = []
	second.on_observe = func(): callbacks.append("observe")
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	var initial := host.reset({})
	assert_array(initial["value"][0].keys()).contains_exactly(["a"])
	assert_array(callbacks).is_empty()
	second.training_paused = false
	var resumed := host.step({"actions": [{"a": 1}]})
	assert_int(_status_code(resumed)).is_equal(STATUS_OK)
	assert_float(resumed["value"]["state"][0]["b"]["reward"]).is_equal(0.0)
	assert_object(second.last_action).is_null()


func test_birth_pausing_during_observation_is_announced_on_resume() -> void:
	var root := _test_root()
	var environment := _dynamic_environment(root)
	var host := _add_host(root)
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	var second = _add_agent(environment, "b", "b")
	var observations: Array[String] = []
	second.on_observe = func():
		observations.append("observe")
		second.training_paused = true
	var birth := host.step({"actions": [{"a": 1}]})
	assert_int(_status_code(birth)).is_equal(STATUS_OK)
	assert_bool(birth["value"]["state"][0].has("b")).is_false()
	var paused := host.step({"actions": [{"a": 1}]})
	assert_int(_status_code(paused)).is_equal(STATUS_OK)
	assert_bool(paused["value"]["state"][0].has("b")).is_false()
	assert_array(observations).contains_exactly(["observe"])
	assert_object(second.last_action).is_null()
	second.on_observe = Callable()
	second.training_paused = false
	var resumed := host.step({"actions": [{"a": 1}]})
	assert_int(_status_code(resumed)).is_equal(STATUS_OK)
	assert_bool(resumed["value"]["state"][0]["b"]["terminated"]).is_false()
	assert_float(resumed["value"]["state"][0]["b"]["reward"]).is_equal(0.0)
	assert_int(_status_code(host.step({"actions": [{"a": 1, "b": 2}]}))).is_equal(STATUS_OK)


func test_agents_joining_after_reset_start_with_fresh_observation_history() -> void:
	for join in ["resume", "readd"]:
		var root := _test_root()
		var environment := _dynamic_environment(root)
		_add_stacker(environment.definitions[1])
		var second = _add_agent(environment, "b", "b")
		_add_stacker(second)
		var host := _add_host(root)
		assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
		assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
		var first_episode := host.step({"actions": [{"a": 1, "b": 2}]})
		assert_dict(first_episode["value"]["state"][0]["b"]["observation"]).is_equal({"Point_0": 2, "Point_1": 0, "Point_2": 0})

		# b misses the next reset: paused through it, or removed and added back afterwards.
		if join == "resume":
			second.training_paused = true
		else:
			environment.remove_child(second)
			assert_int(_status_code(host.step({"actions": [{"a": 1, "b": 1}]}))).is_equal(STATUS_OK)
		var initial := host.reset({})
		assert_array(initial["value"][0].keys()).contains_exactly(["a"])
		if join == "resume":
			second.training_paused = false
		else:
			second.observation = 0
			environment.add_child(second)
		var joined := host.step({"actions": [{"a": 1}]})
		assert_int(_status_code(joined)).is_equal(STATUS_OK)
		assert_dict(joined["value"]["state"][0]["b"]["observation"]).is_equal({"Point_0": 0, "Point_1": 0, "Point_2": 0})

		# Pausing within the episode keeps the history built since joining.
		second.training_paused = true
		assert_int(_status_code(host.step({"actions": [{"a": 1, "b": 2}]}))).is_equal(STATUS_OK)
		second.training_paused = false
		var resumed := host.step({"actions": [{"a": 1}]})
		assert_int(_status_code(resumed)).is_equal(STATUS_OK)
		assert_dict(resumed["value"]["state"][0]["b"]["observation"]).is_equal({"Point_0": 2, "Point_1": 2, "Point_2": 0})


func test_session_activity_tracks_initialization_recoverable_errors_and_close() -> void:
	var root := _test_root()
	_add_environment(root, "Environment", "agent")
	var host := _add_host(root)
	assert_bool(host.is_session_active()).is_false()
	assert_int(_status_code(_start(host))).is_equal(STATUS_OK)
	assert_bool(host.is_session_active()).is_true()
	assert_int(_status_code(host.reset({}))).is_equal(STATUS_OK)
	var invalid := host.step({"actions": [{"agent": "invalid"}]})
	assert_int(_status_code(invalid)).is_equal(STATUS_INVALID_ARGUMENT)
	assert_bool(host.is_session_active()).is_true()
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)
	assert_bool(host.is_session_active()).is_false()
	assert_int(_status_code(host.close())).is_equal(STATUS_OK)
	assert_bool(host.is_session_active()).is_false()
