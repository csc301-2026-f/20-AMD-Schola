# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# US3: the training extension's side of a session, without Python.
#
# ScholaTrainingTestClient makes the same calls ConnectorLoop makes for Python
# (start, define, reset, step, close) and sends them through the real
# HostTrainingBackend to a real ScholaTrainingHost. The connector tests check
# the scene node itself gives up cleanly when Python never shows up.
#
# Needs the training extension built with integration_tests=yes (which needs
# gRPC), so CI runs it on Linux. Without it, the suite is skipped.
extends GdUnitTestSuite

const TestAgent := preload("res://tests/integration/support/us4_test_agent.gd")
const TestEnvironment := preload("res://tests/integration/support/us4_test_environment.gd")
const LineAgent := preload("res://examples/multi_agent/line_agent.gd")
const LineEnvironment := preload("res://examples/multi_agent/line_environment.gd")

const STATUS_NOT_FOUND := 2
const STATUS_FAILED_PRECONDITION := 5
const AUTORESET_DISABLED := 2

var _previous_scene: Node
var _client: RefCounted


func before(
	_do_skip := not ClassDB.class_exists("ScholaTrainingTestClient"),
	_skip_reason := "Build the training extension with integration_tests=yes (needs gRPC) to run this suite."
) -> void:
	pass


func before_test() -> void:
	_previous_scene = get_tree().current_scene
	_client = ClassDB.instantiate("ScholaTrainingTestClient")


func after_test() -> void:
	get_tree().current_scene = _previous_scene
	_client = null


# --- Helpers ---------------------------------------------------------------


# A fresh current scene, because the host looks for environments there.
func _scene_root() -> Node:
	var root := auto_free(Node.new()) as Node
	root.name = "US3TestRoot"
	get_tree().root.add_child(root)
	get_tree().current_scene = root
	return root


# One environment with one agent "walker": Discrete(3) observation and action.
# The test environment ends each episode after two steps.
func _add_environment(root: Node) -> ScholaAgent:
	var environment := TestEnvironment.new() as ScholaEnvironment
	environment.name = "Environment"
	var agent := TestAgent.new() as ScholaAgent
	agent.name = "Walker"
	agent.agent_id = "walker"
	var space := ScholaDiscreteSpace.new()
	space.n = 3
	agent.observation_space = space
	agent.action_space = space
	environment.add_child(agent)
	root.add_child(environment)
	return agent


# The US12 example's environment: "runner" (Box(2) observation, Discrete(3)
# action) and "hopper" (Discrete(10) observation, MultiDiscrete([2, 2]) action).
func _add_two_agent_environment(root: Node) -> ScholaEnvironment:
	var environment := LineEnvironment.new() as ScholaEnvironment
	environment.name = "Environment"

	var runner := LineAgent.new() as ScholaAgent
	runner.name = "Runner"
	runner.agent_id = "runner"
	var runner_observation := ScholaBoxSpace.new()
	runner_observation.low = PackedFloat32Array([0, 0])
	runner_observation.high = PackedFloat32Array([1, 1])
	runner.observation_space = runner_observation
	var runner_action := ScholaDiscreteSpace.new()
	runner_action.n = 3
	runner.action_space = runner_action
	runner.observes_partner = true
	environment.add_child(runner)

	var hopper := LineAgent.new() as ScholaAgent
	hopper.name = "Hopper"
	hopper.agent_id = "hopper"
	var hopper_observation := ScholaDiscreteSpace.new()
	hopper_observation.n = 10
	hopper.observation_space = hopper_observation
	var hopper_action := ScholaMultiDiscreteSpace.new()
	hopper_action.nvec = PackedInt32Array([2, 2])
	hopper.action_space = hopper_action
	hopper.controls = LineAgent.Controls.BUTTONS
	environment.add_child(hopper)

	root.add_child(environment)
	return environment


func _add_host(root: Node) -> Node:
	var host := ScholaTrainingHost.new()
	host.name = "Host"
	root.add_child(host)
	return host


func _assert_ok(result: Dictionary) -> void:
	assert_bool(result.ok).override_failure_message(result.message).is_true()


# --- HostTrainingBackend -------------------------------------------------------


func test_backend_runs_a_whole_session_in_python_order() -> void:
	var root := _scene_root()
	var agent := _add_environment(root)
	_client.use_host(_add_host(root))

	_assert_ok(_client.start(AUTORESET_DISABLED))

	# The definition went host -> Dictionary -> dictionary_to_space() and back.
	var definition: Dictionary = _client.define()
	_assert_ok(definition)
	var walker: Dictionary = definition.value[0]["walker"]
	assert_dict(walker.observation_space).is_equal(agent.observation_space.to_dictionary())
	assert_dict(walker.action_space).is_equal(agent.action_space.to_dictionary())
	assert_str(walker.agent_type).is_equal("walker")

	var reset: Dictionary = _client.reset({0: 7})
	_assert_ok(reset)
	assert_int(reset.value[0]["walker"]).is_equal(0)

	var first: Dictionary = _client.step([{"walker": 2}])
	_assert_ok(first)
	var state: Dictionary = first.value.state[0]["walker"]
	assert_int(state.observation).is_equal(2)
	assert_float(state.reward).is_equal(1.0)
	assert_bool(state.terminated).is_false()

	var second: Dictionary = _client.step([{"walker": 1}])
	_assert_ok(second)
	assert_bool(second.value.state[0]["walker"].terminated).is_true()

	_assert_ok(_client.close())


func test_a_fresh_host_can_train_the_same_agents_after_a_session_closes() -> void:
	# Schola's RLlib trainer opens one session to read the agents and a second
	# to train. The connector gives each session a fresh host, so the first
	# host must hand the environment back when it closes.
	var root := _scene_root()
	var environment := _add_two_agent_environment(root)
	var first_host := _add_host(root)
	_client.use_host(first_host)
	_assert_ok(_client.start(AUTORESET_DISABLED))
	var first_definition: Dictionary = _client.define()
	_assert_ok(first_definition)
	_assert_ok(_client.close())
	first_host.free()

	_client.use_host(_add_host(root))
	_assert_ok(_client.start(AUTORESET_DISABLED))
	var second_definition: Dictionary = _client.define()
	_assert_ok(second_definition)
	# Same agents, same order, same spaces as the first session.
	assert_array(second_definition.value[0].keys()).is_equal(["hopper", "runner"])
	assert_dict(second_definition.value[0]).is_equal(first_definition.value[0])

	_assert_ok(_client.reset({}))
	var step: Dictionary = _client.step([{"runner": 2, "hopper": PackedInt32Array([0, 1])}])
	_assert_ok(step)
	assert_str(step.value.state[0]["runner"].info.agent).is_equal("runner")
	assert_str(step.value.state[0]["hopper"].info.agent).is_equal("hopper")
	assert_int(environment.episode_count).is_equal(1)
	_assert_ok(_client.close())


func test_host_errors_reach_python_unchanged() -> void:
	# No environments: the host's own NOT_FOUND must come back, word for word,
	# as the reply to StartGymConnector.
	var root := _scene_root()
	_client.use_host(_add_host(root))

	var result: Dictionary = _client.start(AUTORESET_DISABLED)

	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(STATUS_NOT_FOUND)
	assert_str(result.message).contains("add at least one trainable environment")


func test_reset_and_step_need_a_definition_first() -> void:
	var root := _scene_root()
	_add_environment(root)
	_client.use_host(_add_host(root))
	_assert_ok(_client.start(AUTORESET_DISABLED))

	var reset: Dictionary = _client.reset({})

	assert_int(reset.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(reset.message).contains("before define()")


func test_a_freed_host_fails_cleanly_instead_of_crashing() -> void:
	var root := _scene_root()
	_add_environment(root)
	var host := _add_host(root)
	_client.use_host(host)
	host.free()

	var start: Dictionary = _client.start(AUTORESET_DISABLED)

	assert_int(start.code).is_equal(STATUS_FAILED_PRECONDITION)
	assert_str(start.message).contains("was freed")
	# Closing after the host is gone has nothing left to do, so it succeeds.
	_assert_ok(_client.close())


# --- ScholaTrainingConnector ----------------------------------------------------


func test_connector_properties_stay_in_range() -> void:
	var connector: Node = auto_free(ClassDB.instantiate("ScholaTrainingConnector"))

	connector.port = 0
	assert_int(connector.port).is_equal(1)
	connector.port = 70000
	assert_int(connector.port).is_equal(65535)
	connector.start_timeout_sec = -5.0
	assert_float(connector.start_timeout_sec).is_equal(0.0)
	assert_bool(connector.is_training()).is_false()


func test_connector_gives_up_and_reports_when_python_never_connects() -> void:
	var root := _scene_root()
	_add_environment(root)
	var connector: Node = ClassDB.instantiate("ScholaTrainingConnector")
	connector.port = 50000 + randi() % 10000
	connector.start_timeout_sec = 0.2
	var errors: Array[String] = []
	connector.training_finished.connect(func(error: String) -> void: errors.append(error))
	root.add_child(connector)

	# The session starts on the first physics frame and waits 0.2 s for Python.
	for frame in 30:
		if not errors.is_empty():
			break
		await get_tree().physics_frame

	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0]).is_not_empty()
	assert_bool(connector.is_training()).is_false()
