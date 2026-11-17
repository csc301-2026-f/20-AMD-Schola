# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# Drives GodotEnvironmentAdapter directly through the native test driver and
# checks its initialize, reset, step, and get_agents contract.
# environment_step_result_test.gd covers _get_step_result parsing and the
# act/observe/result order.
extends GdUnitTestSuite

const STATUS_INVALID_ARGUMENT := 1
const STATUS_NOT_FOUND := 2
const STATUS_FAILED_PRECONDITION := 5


class TestAgent extends ScholaAgent:
	var events: Array = []
	var observation: Variant = 0
	var actions := 0
	# During the hook named by free_during ("act" or "observe"), frees victim.
	var victim: Node
	var free_during := ""

	func _act(_action: Variant) -> void:
		actions += 1
		events.append("act:" + str(name))
		_free_victim("act")

	func _observe() -> Variant:
		events.append("observe:" + str(name))
		_free_victim("observe")
		return observation

	func _free_victim(hook: String) -> void:
		if free_during == hook:
			free_during = ""
			victim.free()


# Deliberately has no _act override.
class ObserveOnlyAgent extends ScholaAgent:
	func _observe() -> Variant:
		return 0


class TestEnvironment extends ScholaEnvironment:
	var events: Array = []
	var results: Dictionary = {}
	var last_seed: Variant
	var last_options: Dictionary = {}
	var draws: Array[int] = []

	func _reset_episode(seed: Variant, options: Dictionary) -> void:
		last_seed = seed
		last_options = options
		draws.append(get_rng().randi())
		events.append("reset")

	func _get_step_result(agent: ScholaAgent) -> Variant:
		events.append("result:" + str(agent.name))
		return results.get(str(agent.name), {"reward": 0})


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


func _space() -> ScholaDiscreteSpace:
	var space := ScholaDiscreteSpace.new()
	space.n = 2
	return space


func _add_agent(parent: Node, environment: TestEnvironment, agent_name: String) -> TestAgent:
	var agent := TestAgent.new()
	agent.name = agent_name
	agent.events = environment.events
	agent.observation_space = _space()
	agent.action_space = _space()
	parent.add_child(agent)
	return agent


func _environment(agent_names: Array = []) -> TestEnvironment:
	var environment: TestEnvironment = auto_free(TestEnvironment.new())
	environment.name = "Arena"
	for agent_name in agent_names:
		_add_agent(environment, environment, agent_name)
	add_child(environment)
	environment.episode_started.connect(func() -> void: environment.events.append("started"))
	environment.episode_ended.connect(func() -> void: environment.events.append("ended"))
	return environment


# Initializes and resets, then clears the events so each test sees only its own.
func _started(agent_names: Array) -> TestEnvironment:
	var environment := _environment(agent_names)
	assert_bool(_driver.call("initialize", environment).ok).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()
	environment.events.clear()
	return environment


func _agent(environment: TestEnvironment, agent_name: String) -> TestAgent:
	return environment.get_node(agent_name) as TestAgent


func test_initialize_reports_resolved_ids_and_skips_nested_environments() -> void:
	var environment := _environment(["Runner"])
	var chaser := _add_agent(environment, environment, "ChaserNode")
	chaser.agent_id = "chaser"
	chaser.agent_type = "hunters"
	var nested := ScholaEnvironment.new()
	nested.name = "Nested"
	environment.add_child(nested)
	_add_agent(nested, environment, "Inner")

	var response: Dictionary = _driver.call("initialize", environment)

	assert_bool(response.ok).override_failure_message(response.message).is_true()
	assert_dict(response.agents).is_equal({"Runner": "Runner", "chaser": "hunters"})


func test_calls_before_initialize_fail_without_touching_output() -> void:
	var environment := _environment(["A"])

	var reset_response: Dictionary = _driver.call("reset", environment)
	assert_int(reset_response.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(reset_response.message).contains("Environment 'Arena': reset() called before initialize()")
	assert_array(reset_response.states.keys()).contains_exactly(["sentinel"])

	var step_response: Dictionary = _driver.call("step_unchecked", environment, {"A": 0})
	assert_int(step_response.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(step_response.message).contains("step() called before reset()")
	assert_array(step_response.states.keys()).contains_exactly(["sentinel"])

	var agents_response: Dictionary = _driver.call("get_agents", environment)
	assert_int(agents_response.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(agents_response.message).contains("get_agents() called before initialize()")
	assert_array(agents_response.agents).contains_exactly(["sentinel"])

	assert_array(environment.events).is_empty()
	# Outside the scene tree, the node hands out no adapter at all.
	var detached: TestEnvironment = auto_free(TestEnvironment.new())
	assert_bool(_driver.call("initialize", detached).ok).is_false()


func test_failed_initialize_leaves_the_adapter_ready_for_a_retry() -> void:
	var environment := _environment()
	var empty: Dictionary = _driver.call("initialize", environment)
	assert_int(empty.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(empty.message).contains("Environment 'Arena'").contains("Add a ScholaAgent node")
	assert_dict(empty.agents).is_equal({"sentinel": "sentinel"})

	var agent := _add_agent(environment, environment, "A")
	agent.action_space = null
	var unset: Dictionary = _driver.call("initialize", environment)
	assert_int(unset.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(unset.message).contains("Agent 'A'").contains("action_space is not set")
	assert_dict(unset.agents).is_equal({"sentinel": "sentinel"})

	agent.action_space = _space()
	var group := Node.new()
	group.name = "Group"
	environment.add_child(group)
	var duplicate := _add_agent(group, environment, "Duplicate")
	duplicate.agent_id = "A"
	var clash: Dictionary = _driver.call("initialize", environment)
	assert_int(clash.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(clash.message).contains("Duplicate agent ID 'A'")
	assert_dict(clash.agents).is_equal({"sentinel": "sentinel"})

	group.free()
	var fixed: Dictionary = _driver.call("initialize", environment)
	assert_bool(fixed.ok).override_failure_message(fixed.message).is_true()
	assert_dict(fixed.agents).is_equal({"A": "A"})


func test_initialize_twice_fails_and_keeps_the_first_agent_set() -> void:
	var environment := _environment(["A"])
	assert_bool(_driver.call("initialize", environment).ok).is_true()
	_add_agent(environment, environment, "B")

	var again: Dictionary = _driver.call("initialize", environment)

	assert_int(again.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(again.message).contains("initialize() was already called")
	assert_dict(again.agents).is_equal({"sentinel": "sentinel"})
	# B joined after the first initialize(), so the adapter never drives it.
	var reset_response: Dictionary = _driver.call("reset", environment)
	assert_bool(reset_response.ok).is_true()
	assert_array(reset_response.states.keys()).contains_exactly(["A"])
	assert_array(environment.events).contains_exactly(["reset", "observe:A", "started"])


func test_reset_seeds_the_rng_and_forwards_seed_and_options() -> void:
	var environment := _environment(["A"])
	assert_bool(_driver.call("initialize", environment).ok).is_true()

	assert_bool(_driver.call("reset", environment, {"seed": 42, "options": {"track": "hard"}}).ok).is_true()
	assert_int(typeof(environment.last_seed)).is_equal(TYPE_INT)
	assert_int(environment.last_seed).is_equal(42)
	assert_dict(environment.last_options).is_equal({"track": "hard"})
	assert_bool(_driver.call("reset", environment, {"seed": 7}).ok).is_true()
	assert_int(environment.last_seed).is_equal(7)
	assert_dict(environment.last_options).is_empty()
	assert_bool(_driver.call("reset", environment, {"seed": 42}).ok).is_true()

	# _reset_episode draws once from get_rng(), so each draw shows the seed it got.
	var expected := RandomNumberGenerator.new()
	expected.seed = 42
	var draw_42 := expected.randi()
	expected.seed = 7
	var draw_7 := expected.randi()
	assert_array(environment.draws).contains_exactly([draw_42, draw_7, draw_42])


func test_reset_without_seed_keeps_the_rng_running() -> void:
	var environment := _environment(["A"])
	assert_bool(_driver.call("initialize", environment).ok).is_true()

	assert_bool(_driver.call("reset", environment, {"seed": 42}).ok).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()

	assert_int(typeof(environment.last_seed)).is_equal(TYPE_NIL)
	var expected := RandomNumberGenerator.new()
	expected.seed = 42
	var first := expected.randi()
	var second := expected.randi()
	assert_array(environment.draws).contains_exactly([first, second])


func test_reset_observes_every_agent_then_announces_the_episode() -> void:
	var environment := _environment(["A", "B"])
	_agent(environment, "A").observation = 1
	assert_bool(_driver.call("initialize", environment).ok).is_true()

	var response: Dictionary = _driver.call("reset", environment)

	assert_bool(response.ok).override_failure_message(response.message).is_true()
	assert_array(environment.events).contains_exactly(["reset", "observe:A", "observe:B", "started"])
	assert_array(response.states.keys()).contains_exactly_in_any_order(["A", "B"])
	assert_int(response.states.A.observation).is_equal(1)
	assert_int(response.states.B.observation).is_equal(0)
	assert_dict(response.states.A.info).is_empty()
	assert_int(environment.get_episode_step()).is_equal(0)


func test_failed_reset_blocks_step_until_a_reset_succeeds() -> void:
	var environment := _started(["A", "B"])
	var b := _agent(environment, "B")
	b.observation = 5 # Outside Discrete(2).

	var failed: Dictionary = _driver.call("reset", environment)

	assert_int(failed.code).is_equal(STATUS_INVALID_ARGUMENT)
	assert_str(failed.message).contains("Agent 'B': _observe() returned a bad value")
	assert_array(failed.states.keys()).contains_exactly(["sentinel"])
	assert_bool(environment.events.has("started")).is_false()
	# The last successful reset no longer counts: step() waits for a new one.
	var blocked: Dictionary = _driver.call("step", environment, {"A": 0})
	assert_int(blocked.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(blocked.message).contains("step() called before reset()")
	assert_int(_agent(environment, "A").actions).is_equal(0)

	b.observation = 0
	assert_bool(_driver.call("reset", environment).ok).is_true()
	assert_bool(_driver.call("step", environment, {"A": 0, "B": 0}).ok).is_true()


func test_step_rejects_a_bad_batch_before_any_agent_moves() -> void:
	var environment := _started(["A", "B"])

	# Actions are checked in ID order, so A passes before the bad entry is found.
	var unknown: Dictionary = _driver.call("step_unchecked", environment, {"A": 0, "Ghost": 0})
	assert_int(unknown.code).is_equal(STATUS_NOT_FOUND)
	assert_str(unknown.message).contains("Agent 'Ghost': not part of this environment")
	assert_array(unknown.states.keys()).contains_exactly(["sentinel"])
	for action in [2, -1]:
		var rejected: Dictionary = _driver.call("step_unchecked", environment, {"A": 0, "B": action})
		assert_int(rejected.code).is_equal(STATUS_INVALID_ARGUMENT)
		assert_str(rejected.message).contains("Agent 'B': rejected action")
		assert_array(rejected.states.keys()).contains_exactly(["sentinel"])

	assert_array(environment.events).is_empty()
	assert_int(environment.get_episode_step()).is_equal(0)
	assert_bool(_driver.call("step_unchecked", environment, {"A": 0, "B": 1}).ok).is_true()


func test_finished_agents_sit_out_until_the_last_one_ends_the_episode() -> void:
	var environment := _started(["A", "B"])
	environment.results = {"A": {"reward": 1, "terminated": true}}
	assert_bool(_driver.call("step", environment, {"A": 0, "B": 0}).ok).is_true()
	assert_bool(environment.events.has("ended")).is_false()

	var finished: Dictionary = _driver.call("step", environment, {"A": 0, "B": 0})
	assert_int(finished.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(finished.message).contains("Agent 'A': already finished this episode")
	assert_int(_agent(environment, "B").actions).is_equal(1)

	environment.events.clear()
	environment.results["B"] = {"reward": 1, "truncated": true}
	var last: Dictionary = _driver.call("step", environment, {"B": 0})
	assert_bool(last.ok).override_failure_message(last.message).is_true()
	assert_array(last.states.keys()).contains_exactly(["B"])
	assert_array(environment.events).contains_exactly(["act:B", "observe:B", "result:B", "ended"])
	assert_int(environment.get_episode_step()).is_equal(2)

	assert_bool(_driver.call("reset", environment).ok).is_true()
	environment.results = {}
	assert_bool(_driver.call("step", environment, {"A": 0, "B": 0}).ok).is_true()


func test_freed_agent_fails_before_any_agent_moves() -> void:
	var environment := _started(["A", "B"])
	_agent(environment, "B").free()

	var step_response: Dictionary = _driver.call("step", environment, {"A": 0, "B": 0})
	assert_int(step_response.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(step_response.message).contains("Agent 'B': the agent node was freed")
	assert_array(step_response.states.keys()).contains_exactly(["sentinel"])
	assert_int(_agent(environment, "A").actions).is_equal(0)

	var reset_response: Dictionary = _driver.call("reset", environment)
	assert_int(reset_response.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(reset_response.message).contains("Agent 'B': the agent node was freed")
	assert_array(reset_response.states.keys()).contains_exactly(["sentinel"])

	var agents_response: Dictionary = _driver.call("get_agents", environment)
	assert_int(agents_response.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(agents_response.message).contains("Agent 'B': the agent node was freed")
	assert_array(agents_response.agents).contains_exactly(["sentinel"])


func test_agent_freed_mid_step_stops_the_step_without_partial_output() -> void:
	var expected_events := {
		"act": ["act:A"],
		"observe": ["act:A", "act:B", "observe:A", "result:A"],
	}
	for hook in expected_events:
		var environment := _started(["A", "B"])
		var a := _agent(environment, "A")
		a.victim = _agent(environment, "B")
		a.free_during = hook

		var response: Dictionary = _driver.call("step", environment, {"A": 0, "B": 0})

		assert_int(response.code).is_equal(STATUS_FAILED_PRECONDITION)
		assert_str(response.message).contains("Agent 'B': the agent node was freed")
		assert_array(response.states.keys()).contains_exactly(["sentinel"])
		assert_array(environment.events).contains_exactly(expected_events[hook])
		assert_int(environment.get_episode_step()).is_equal(0)


func test_bad_observation_during_step_fails_after_agents_acted() -> void:
	var environment := _started(["A", "B"])
	_agent(environment, "B").observation = 5 # Outside Discrete(2).

	var response: Dictionary = _driver.call("step", environment, {"A": 0, "B": 0})

	assert_int(response.code).is_equal(STATUS_INVALID_ARGUMENT)
	assert_str(response.message).contains("Agent 'B': _observe() returned a bad value")
	assert_array(response.states.keys()).contains_exactly(["sentinel"])
	assert_array(environment.events).contains_exactly(["act:A", "act:B", "observe:A", "result:A", "observe:B"])
	assert_int(environment.get_episode_step()).is_equal(0)


func test_missing_act_hook_is_passed_through_from_the_agent() -> void:
	var environment := _environment()
	var agent := ObserveOnlyAgent.new()
	agent.name = "Lazy"
	agent.observation_space = _space()
	agent.action_space = _space()
	environment.add_child(agent)
	assert_bool(_driver.call("initialize", environment).ok).is_true()
	assert_bool(_driver.call("reset", environment).ok).is_true()

	var response: Dictionary = _driver.call("step", environment, {"Lazy": 0})

	assert_int(response.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(response.message).contains("Agent 'Lazy': _act() is not overridden")
	assert_array(response.states.keys()).contains_exactly(["sentinel"])


func test_get_agents_returns_live_agents_in_scene_tree_order() -> void:
	var environment := _environment(["Zed"])
	var group := Node.new()
	group.name = "Group"
	environment.add_child(group)
	_add_agent(group, environment, "Alpha")
	var last := _add_agent(environment, environment, "Mid")
	last.agent_id = "aaa"
	assert_bool(_driver.call("initialize", environment).ok).is_true()

	var response: Dictionary = _driver.call("get_agents", environment)

	assert_bool(response.ok).override_failure_message(response.message).is_true()
	# Scene-tree order, not ID order ("Alpha", "Zed", "aaa").
	assert_array(response.agents).contains_exactly(["Zed", "Alpha", "Mid"])
