# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# US12: two agents with different spaces trained in one environment.
#
# Uses the two-agent example (examples/multi_agent): "runner" observes Box(2)
# [own, partner position] / 9 and acts with Discrete(3) (0 back, 1 stay,
# 2 forward); "hopper" observes Discrete(10) and acts with MultiDiscrete([2, 2])
# [back, forward]. ScholaTrainingTestClient plays Python and drives the real
# HostTrainingBackend and ScholaTrainingHost, as in training_connector_test.gd.
#
# Needs the training extension built with integration_tests=yes (which needs
# gRPC). Without it, the suite is skipped.
extends GdUnitTestSuite

const LineAgent := preload("res://examples/multi_agent/line_agent.gd")
const LineEnvironment := preload("res://examples/multi_agent/line_environment.gd")

const STATUS_INVALID_ARGUMENT := 1
const STATUS_FAILED_PRECONDITION := 5
const AUTORESET_DISABLED := 2

# Hopper actions, as [back pressed, forward pressed].
const HOP_FORWARD := [0, 1]
const HOP_BACK := [1, 0]
const HOP_STAY := [0, 0]
# Runner actions.
const RUN_BACK := 0
const RUN_STAY := 1
const RUN_FORWARD := 2

var _previous_scene: Node
var _client: RefCounted
var _environment: ScholaEnvironment
var _runner: ScholaAgent
var _hopper: ScholaAgent


func before(
	_do_skip := not ClassDB.class_exists("ScholaTrainingTestClient"),
	_skip_reason := "Build the training extension with integration_tests=yes (needs gRPC) to run this suite."
) -> void:
	pass


func before_test() -> void:
	_previous_scene = get_tree().current_scene
	_client = ClassDB.instantiate("ScholaTrainingTestClient")

	var root := auto_free(Node.new()) as Node
	root.name = "US12TestRoot"
	get_tree().root.add_child(root)
	get_tree().current_scene = root
	_add_two_agent_environment(root)

	var host := ScholaTrainingHost.new()
	host.name = "Host"
	root.add_child(host)
	_client.use_host(host)


func after_test() -> void:
	get_tree().current_scene = _previous_scene
	_client = null


# --- Helpers ---------------------------------------------------------------


func _add_two_agent_environment(root: Node) -> void:
	_environment = LineEnvironment.new() as ScholaEnvironment
	_environment.name = "Environment"

	_runner = LineAgent.new() as ScholaAgent
	_runner.name = "Runner"
	_runner.agent_id = "runner"
	var runner_observation := ScholaBoxSpace.new()
	runner_observation.low = PackedFloat32Array([0, 0])
	runner_observation.high = PackedFloat32Array([1, 1])
	_runner.observation_space = runner_observation
	var runner_action := ScholaDiscreteSpace.new()
	runner_action.n = 3
	_runner.action_space = runner_action
	_runner.observes_partner = true
	_environment.add_child(_runner)

	_hopper = LineAgent.new() as ScholaAgent
	_hopper.name = "Hopper"
	_hopper.agent_id = "hopper"
	var hopper_observation := ScholaDiscreteSpace.new()
	hopper_observation.n = 10
	_hopper.observation_space = hopper_observation
	var hopper_action := ScholaMultiDiscreteSpace.new()
	hopper_action.nvec = PackedInt32Array([2, 2])
	_hopper.action_space = hopper_action
	_hopper.controls = LineAgent.Controls.BUTTONS
	_environment.add_child(_hopper)

	root.add_child(_environment)


# Python's start and define, then the first reset.
func _start_episode() -> void:
	_assert_ok(_client.start(AUTORESET_DISABLED))
	_assert_ok(_client.define())
	_assert_ok(_client.reset({}))


func _step(actions: Dictionary) -> Dictionary:
	var converted := {}
	for id in actions:
		var action: Variant = actions[id]
		converted[id] = PackedInt32Array(action) if action is Array else action
	return _client.step([converted])


# The per-agent results of a successful step: {agent_id: {...}}.
func _results(step: Dictionary) -> Dictionary:
	_assert_ok(step)
	return step.value.state[0]


func _assert_ok(result: Dictionary) -> void:
	assert_bool(result.ok).override_failure_message(result.message).is_true()


# --- Definition --------------------------------------------------------------


func test_definition_lists_both_agents_with_their_own_spaces() -> void:
	_assert_ok(_client.start(AUTORESET_DISABLED))

	var definition: Dictionary = _client.define()

	_assert_ok(definition)
	var agents: Dictionary = definition.value[0]
	# Agents are identified, and ordered, by ID rather than scene order.
	assert_array(agents.keys()).is_equal(["hopper", "runner"])
	assert_dict(agents.runner.observation_space).is_equal(_runner.observation_space.to_dictionary())
	assert_dict(agents.runner.action_space).is_equal(_runner.action_space.to_dictionary())
	assert_dict(agents.hopper.observation_space).is_equal(_hopper.observation_space.to_dictionary())
	assert_dict(agents.hopper.action_space).is_equal(_hopper.action_space.to_dictionary())
	assert_str(agents.runner.agent_type).is_equal("runner")
	assert_str(agents.hopper.agent_type).is_equal("hopper")


# --- Routing -----------------------------------------------------------------


func test_each_agent_gets_its_own_action_and_result() -> void:
	_start_episode()

	var results := _results(_step({"runner": RUN_BACK, "hopper": HOP_FORWARD}))

	# Runner stepped back from 0, so it stays at 0 and pays the step cost.
	var runner: Dictionary = results.runner
	assert_int(_runner.position).is_equal(0)
	assert_float(runner.reward).is_equal_approx(-0.05, 0.0001)
	assert_str(runner.info.agent).is_equal("runner")
	assert_str(runner.info.position).is_equal("0")
	# Every agent acts before any is observed, so the runner already sees the
	# hopper's new position.
	assert_float(runner.observation[0]).is_equal(0.0)
	assert_float(runner.observation[1]).is_equal_approx(1.0 / 9.0, 0.0001)

	# Hopper pressed forward, so it moved to 1 and earned its progress.
	var hopper: Dictionary = results.hopper
	assert_int(_hopper.position).is_equal(1)
	assert_int(hopper.observation).is_equal(1)
	assert_float(hopper.reward).is_equal_approx(0.95, 0.0001)
	assert_str(hopper.info.agent).is_equal("hopper")
	assert_str(hopper.info.position).is_equal("1")

	for result: Dictionary in [runner, hopper]:
		assert_bool(result.terminated).is_false()
		assert_bool(result.truncated).is_false()


func test_shared_rewards_give_every_acting_agent_the_team_average() -> void:
	_environment.reward_mode = "shared"
	_start_episode()

	var results := _results(_step({"runner": RUN_BACK, "hopper": HOP_FORWARD}))

	# The team average of -0.05 and 0.95.
	assert_float(results.runner.reward).is_equal_approx(0.45, 0.0001)
	assert_float(results.hopper.reward).is_equal_approx(0.45, 0.0001)


# --- Episode completion ------------------------------------------------------


func test_an_agent_that_finishes_early_stops_acting_and_keeps_its_final_result() -> void:
	_start_episode()
	_hopper.position = 8

	var first := _results(_step({"runner": RUN_FORWARD, "hopper": HOP_FORWARD}))

	# Hopper reached 9: terminated, with the goal bonus.
	assert_bool(first.hopper.terminated).is_true()
	assert_float(first.hopper.reward).is_equal_approx(5.95, 0.0001)
	assert_bool(first.runner.terminated).is_false()

	# Only the runner acts now; the episode goes on.
	var second := _results(_step({"runner": RUN_FORWARD}))

	assert_int(_runner.position).is_equal(2)
	assert_bool(second.runner.terminated).is_false()
	# Hopper did not act again, and its final result is repeated unchanged,
	# as Schola's protocol expects until the whole episode ends.
	assert_int(_hopper.acted_on_step).is_equal(0)
	assert_dict(second.hopper).is_equal(first.hopper)


func test_unfinished_agents_are_truncated_at_the_step_limit() -> void:
	_environment.max_steps = 2
	_start_episode()

	var first := _results(_step({"runner": RUN_STAY, "hopper": HOP_STAY}))
	var second := _results(_step({"runner": RUN_STAY, "hopper": HOP_STAY}))

	for id in ["runner", "hopper"]:
		assert_bool(first[id].truncated).is_false()
		assert_bool(second[id].truncated).is_true()
		# Truncated, not terminated: neither agent reached the goal.
		assert_bool(second[id].terminated).is_false()


func test_agent_ids_and_order_stay_the_same_over_several_episodes() -> void:
	_environment.max_steps = 1
	_assert_ok(_client.start(AUTORESET_DISABLED))
	_assert_ok(_client.define())

	for episode in 3:
		var reset: Dictionary = _client.reset({})
		_assert_ok(reset)
		assert_array(reset.value[0].keys()).is_equal(["hopper", "runner"])
		# Every episode starts both agents at 0.
		assert_int(reset.value[0].hopper).is_equal(0)

		var results := _results(_step({"runner": RUN_FORWARD, "hopper": HOP_FORWARD}))
		assert_array(results.keys()).is_equal(["hopper", "runner"])
		assert_str(results.runner.info.episode).is_equal(str(episode + 1))
		assert_bool(results.runner.truncated).is_true()
		assert_bool(results.hopper.truncated).is_true()

	assert_int(_environment.episode_count).is_equal(3)
	_assert_ok(_client.close())


# --- Invalid actions and session failure -----------------------------------


func test_a_missing_action_ends_the_session_before_anyone_moves() -> void:
	_start_episode()

	var step := _step({"runner": RUN_FORWARD})

	assert_bool(step.ok).is_false()
	assert_int(step.code).is_equal(STATUS_INVALID_ARGUMENT)
	assert_str(step.message).contains("missing action for unfinished agent hopper")
	# Nothing moved: the actions are checked before any agent acts.
	assert_int(_runner.position).is_equal(0)
	assert_int(_hopper.position).is_equal(0)
	# A bad action set is a protocol error, so the session is over.
	assert_bool(_client.reset({}).ok).is_false()
	_assert_ok(_client.close())


func test_an_action_for_a_finished_agent_ends_the_session() -> void:
	_start_episode()
	_hopper.position = 8
	_assert_ok(_step({"runner": RUN_FORWARD, "hopper": HOP_FORWARD}))

	var step := _step({"runner": RUN_FORWARD, "hopper": HOP_FORWARD})

	assert_bool(step.ok).is_false()
	assert_int(step.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(step.message).contains("'hopper': already finished this episode")
	assert_int(_runner.position).is_equal(1)
	assert_bool(_client.reset({}).ok).is_false()
	_assert_ok(_client.close())


func test_removing_an_agent_mid_session_fails_the_step_and_closes_cleanly() -> void:
	_start_episode()
	_hopper.free()

	var step := _step({"runner": RUN_FORWARD, "hopper": HOP_FORWARD})

	assert_bool(step.ok).is_false()
	assert_str(step.message).contains("hopper")
	_assert_ok(_client.close())
