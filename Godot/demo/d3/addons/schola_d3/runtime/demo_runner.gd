# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

class_name ScholaDemoRunner
extends Node
## Hands control of the grid to the keyboard, the Python trainer or an ONNX policy. Every mode runs
## the environment through one native ScholaTrainingHost session (US4), which calls the US1 hooks
## on the environment and agent nodes. Training requests arrive through ScholaLocalConnector, the
## stand-in for US3's gRPC connector; this script plays the part of US3's ConnectorLoop.

signal mode_changed(mode: Mode)
signal log_message(text: String, is_error: bool)
signal trainer_progress(stats: Dictionary)
signal action_chosen(action: Variant, source: String)
signal connection_state_changed(state: ScholaLocalConnector.State, message: String)
signal episode_started(episode: int)
signal step_completed(state: Dictionary)
signal episode_finished(outcome: String, total_reward: float)

enum Mode { MANUAL, WAITING, TRAINING, STOPPING, POLICY, CLOSED, EDITING }

const FRAME_WAIT_BUDGET_USEC := 10000
const GROUP := "schola_demo_runner"
const ENVIRONMENT_ID := 0
const STATUS_OK := 0
const RUNNING := "running"
const TIMEOUT := "timeout"
## schola::AutoResetMode::DISABLED. The session is defined once, so its mode is fixed.
const AUTORESET_DISABLED := 2
const AUTORESET_NAMES := ["SAME_STEP", "NEXT_STEP", "DISABLED"]
## schola::StatusCode, in declaration order.
const STATUS_NAMES := [
	"OK", "INVALID_ARGUMENT", "NOT_FOUND", "INVALID_DATA", "INCOMPATIBLE",
	"FAILED_PRECONDITION", "TIMEOUT", "CLOSED", "RUNTIME_FAILURE",
]

@export var environment: ScholaEnvironment
@export_group("Training client")
@export var port := 8000
@export var start_timeout_sec := 45.0
@export var step_timeout_sec := 60.0
@export var auto_launch_trainer := true
@export var python_executable := "python"
@export_file("*.py") var trainer_script := "res://python/trainer.py"
@export var trainer_episodes := 300
@export_file("*.json") var policy_out_path := "res://policies/q_policy.json"
@export_group("ONNX policy")
## Its model_path is where the trainer exports the ONNX model.
@export var policy: ScholaOnnxPolicy
@export_group("Pacing")
@export_range(1, 2000) var steps_per_second := 20.0
@export var reset_delay := 0.8

var mode := Mode.MANUAL
var connector: ScholaLocalConnector
var connection_state := ScholaLocalConnector.State.IDLE
var policy_source := ""

## The host session's definition, as one {agent_id: definition} per environment.
var definition: Array = []
var agent: ScholaAgent
var agent_id := ""

var episode := 0
var cumulative_reward := 0.0
var outcome := RUNNING
var last_observation: Variant = null

## Set from the command line by a parallel-training launcher; see _apply_command_line().
var instance_label := ""
var listen_on_start := false
var quit_after_training := false
## UDP port of the parallel viewer (demo/parallel.tscn); 0 when no viewer is watching.
var viewer_port := 0

var _host: ScholaTrainingHost
var _policy_state: ScholaPolicyState
var _pid := -1
var _step_budget := 0.0
var _reset_timer := 0.0
var _stop_deadline := 0.0
var _viewer: PacketPeerUDP
var _viewer_dirty := true
var _total_steps := 0
var _finished_episodes: Array = []
var _last_progress := {}


func _ready() -> void:
	# Release templates disable --script overrides; run the shared checks from
	# an application argument inside the exported game's normal scene tree.
	if "--smoke-test" in OS.get_cmdline_user_args():
		var suite: Node = load("res://tests/d3_smoke_suite.gd").new()
		get_tree().root.add_child.call_deferred(suite)
		return
	add_to_group(GROUP)
	_apply_command_line()
	# The host discovers environments under the current scene, which is set after _ready().
	_open_session.call_deferred()


func _exit_tree() -> void:
	_report_to_viewer()
	if connector != null:
		connector.close("Godot is shutting down.", false)
	_kill_trainer()


func is_episode_over() -> bool:
	return outcome != RUNNING


## Options after `--` on the Godot command line, used by python/train_parallel.py:
##   --port=N               listen for the trainer on port N
##   --speed=N              steps per second
##   --train                listen as soon as the scene starts, for an externally launched trainer
##   --quit-after-training  quit when the training session ends
func _apply_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
			instance_label = ":%d" % port
		elif arg.begins_with("--speed="):
			steps_per_second = clampf(float(arg.get_slice("=", 1)), 1.0, 5000.0)
		elif arg == "--train":
			listen_on_start = true
			auto_launch_trainer = false
		elif arg == "--quit-after-training":
			quit_after_training = true
		elif arg.begins_with("--viewer="):
			viewer_port = int(arg.get_slice("=", 1))
	if viewer_port > 0:
		_viewer = PacketPeerUDP.new()
		_viewer.bind(0, "127.0.0.1")
		_viewer.set_dest_address("127.0.0.1", viewer_port)
		trainer_progress.connect(func(stats: Dictionary): _last_progress = stats; _viewer_dirty = true)
	if instance_label != "":
		DisplayServer.window_set_title("Schola D3 %s" % instance_label)


func start_training() -> void:
	if mode != Mode.MANUAL and mode != Mode.POLICY:
		return
	_clear_policy()
	_set_mode(Mode.MANUAL)
	connector = ScholaLocalConnector.new()
	connector.start_timeout_sec = start_timeout_sec
	connector.step_timeout_sec = step_timeout_sec
	connector.state_changed.connect(_on_connection_state_changed)
	connector.notification_received.connect(_on_trainer_notification)
	if not connector.open(port):
		return
	if not auto_launch_trainer:
		_log("run: python python/trainer.py --port %d" % port)
		return
	var args := PackedStringArray([
		ProjectSettings.globalize_path(trainer_script),
		"--port", str(port),
		"--episodes", str(trainer_episodes),
		"--policy-out", ProjectSettings.globalize_path(policy_out_path),
	])
	if policy != null and policy.model_path != "":
		args.append_array(["--onnx-out", ProjectSettings.globalize_path(policy.model_path)])
	_pid = OS.create_process(python_executable, args, true)
	if _pid == -1:
		_log("could not launch '%s'; run python/trainer.py yourself" % python_executable, true)
	else:
		_log("launched trainer (pid %d)" % _pid)


func stop_run() -> void:
	if mode == Mode.CLOSED:
		_log("reloading the scene to open a new training host session")
		get_tree().reload_current_scene()
		return
	if mode == Mode.TRAINING and connector != null and connector.state == ScholaLocalConnector.State.TRAINING:
		connector.request_stop("Stopped by the user in Godot; save the policy and close the session.")
		_set_mode(Mode.STOPPING)
		_stop_deadline = Time.get_ticks_msec() / 1000.0 + 3.0
		_log("asked the trainer to save and stop")
		return
	if connector != null and connector.is_active():
		connector.close("Run reset by the user.", false)
		_set_connection_state(ScholaLocalConnector.State.CLOSED, "Run reset by the user.")
	_kill_trainer()
	_clear_policy()
	_resume_manual("run reset; keyboard controls the agent")


func load_onnx_policy() -> void:
	if mode != Mode.MANUAL and mode != Mode.POLICY:
		_log("stop training before loading a policy", true)
		return
	if policy == null:
		_log("set a ScholaOnnxPolicy in the Runner's policy property", true)
		return
	# load() picks up a model the trainer re-exported to the same path; initialize() then checks
	# the model against the agent's spaces.
	var error := policy.load()
	if error == OK:
		error = policy.initialize(agent)
	if error != OK:
		var hint := " Press Train and then Stop to create it." if error == ERR_FILE_NOT_FOUND else ""
		_log("could not load ONNX policy (%s): %s.%s" % [error_string(error), policy.get_last_error(), hint], true)
		return
	_policy_state = policy.create_state()
	if _policy_state == null:
		_log("could not create a policy state: %s" % policy.get_last_error(), true)
		return
	if environment.has_method("check_policy_map"):
		var warning: String = environment.call("check_policy_map", policy.model_path)
		if warning != "":
			_log(warning, true)
	policy_source = "ONNX policy"
	_set_mode(Mode.POLICY)
	_reset_episode()
	_log("loaded ONNX policy %s (inputs %s, outputs %s)" % [policy.model_path, policy.get_input_names(), policy.get_output_names()])


## Pauses play so the map can be edited. The scene reloads to leave this mode, because the host
## session's spaces are fixed once it is defined.
func begin_map_edit() -> bool:
	if mode != Mode.MANUAL and mode != Mode.POLICY:
		_log("stop training before editing the map", true)
		return false
	_clear_policy()
	_set_mode(Mode.EDITING)
	_log("editing the map: click toggles a hazard, right click moves the goal")
	return true


func run_validation_check() -> void:
	if agent == null:
		return
	var cases := [
		[agent.action_space, 7, "action 7"],
		[agent.action_space, 1.5, "action 1.5 (float)"],
		[agent.observation_space, PackedFloat32Array([1, 2, 3]), "3-value observation"],
		[agent.observation_space, PackedFloat32Array([9, 0, 0, 0]), "observation x = 9"],
		[agent.observation_space, PackedFloat32Array([NAN, 0, 0, 0]), "NaN observation"],
		[agent.observation_space, [0, 0, 0, 0], "Array instead of PackedFloat32Array"],
	]
	_log("US2 validation check:")
	for case in cases:
		var error: String = case[0].get_validation_error(case[1])
		_log("  %s -> %s" % [case[2], error if error != "" else "accepted"], error != "", false)
	var good := agent.observation_space.get_validation_error(last_observation)
	_log("  current observation -> %s" % (good if good != "" else "accepted"), good != "")


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.MANUAL or is_episode_over():
		return
	var actions := {"ui_up": 0, "ui_down": 1, "ui_left": 2, "ui_right": 3}
	for input_name in actions:
		if event.is_action_pressed(input_name):
			if not _check(_step(actions[input_name], "keyboard"), "step"):
				_resume_manual("keyboard controls the agent")
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	_report_to_viewer()
	if connector != null:
		connector.poll()
	if mode == Mode.STOPPING and Time.get_ticks_msec() / 1000.0 > _stop_deadline:
		_log("trainer did not stop in time; closing", true)
		stop_run()

	if (mode == Mode.MANUAL or mode == Mode.POLICY) and is_episode_over():
		_reset_timer += delta
		if _reset_timer >= reset_delay:
			_reset_timer = 0.0
			if not _check(_reset_episode(), "reset"):
				_resume_manual("keyboard controls the agent")
		return

	_step_budget += delta * steps_per_second
	var frame_deadline := Time.get_ticks_usec() + FRAME_WAIT_BUDGET_USEC
	while _step_budget >= 1.0:
		if not _run_one_step(frame_deadline):
			break
		_step_budget -= 1.0
	_step_budget = minf(_step_budget, 1.0)


func _run_one_step(frame_deadline: int) -> bool:
	match mode:
		Mode.TRAINING:
			var request := connector.poll_request()
			while request.is_empty() and connector.is_active() and Time.get_ticks_usec() < frame_deadline:
				OS.delay_usec(50)
				connector.poll()
				request = connector.poll_request()
			if request.is_empty() or mode != Mode.TRAINING:
				return false
			_handle_request(request)
			return true
		Mode.POLICY:
			if is_episode_over():
				return false
			var action: Variant = policy.infer(last_observation, _policy_state)
			if action == null:
				_log("ONNX inference failed: %s" % policy.get_last_error(), true)
				stop_run()
				return false
			if not _check(_step(action, "ONNX policy"), "step"):
				_resume_manual("keyboard controls the agent")
				return false
			return true
	return false


# --- Host session -----------------------------------------------------------------------------


func _open_session() -> void:
	var agents: Array = environment.get_agents() if environment != null else []
	if agents.is_empty():
		_close_mode("the Runner's environment has no ScholaAgent")
		return
	agent = agents[0]
	_host = ScholaTrainingHost.new()
	_host.name = "TrainingHost"
	add_child(_host)
	if not _check(_host.initialize_session(), "initialize the training session"):
		_close_mode("the scene could not start a training session")
		return
	if not _check(_host.set_autoreset_mode(AUTORESET_DISABLED), "set the autoreset mode"):
		_close_mode("the scene could not start a training session")
		return
	var defined := _host.define()
	if not _check(defined, "define the training session"):
		_close_mode("the scene could not start a training session")
		return
	definition.clear()
	for environment_definition in defined.value.environments:
		definition.append(environment_definition.agents)
	agent_id = definition[ENVIRONMENT_ID].keys()[0]
	_log("ScholaTrainingHost session ready: %d environment(s), agent %s, autoreset DISABLED" % [definition.size(), agent_id])
	_resume_manual("keyboard controls the agent")
	if listen_on_start and mode == Mode.MANUAL:
		start_training()


func _reset_episode(seed: Variant = null, options := {}) -> Dictionary:
	var settings := {}
	if seed != null:
		settings["seed"] = seed
	if not options.is_empty():
		settings["options"] = options
	var result := _host.reset({ENVIRONMENT_ID: settings})
	if result.status.code != STATUS_OK:
		return result
	var state: Dictionary = result.value[ENVIRONMENT_ID][agent_id]
	episode += 1
	cumulative_reward = 0.0
	outcome = RUNNING
	last_observation = state.observation
	_reset_timer = 0.0
	if _policy_state != null:
		_policy_state.reset()
	_viewer_dirty = true
	episode_started.emit(episode)
	return result


func _step(action: Variant, source: String) -> Dictionary:
	action_chosen.emit(action, source)
	var result := _host.step({"actions": [{agent_id: action}]})
	if result.status.code != STATUS_OK:
		return result
	var state: Dictionary = result.value.state[ENVIRONMENT_ID][agent_id]
	# With autoreset DISABLED, stepping a finished episode returns its last state again.
	if is_episode_over():
		return result
	cumulative_reward += state.reward
	last_observation = state.observation
	_total_steps += 1
	_viewer_dirty = true
	if state.terminated or state.truncated:
		outcome = state.info.get("outcome", TIMEOUT if state.truncated else "terminated")
	step_completed.emit(state)
	if is_episode_over():
		_finished_episodes.append([cumulative_reward, outcome])
		episode_finished.emit(outcome, cumulative_reward)
	return result


## Logs a failed host result. Returns true when the result is OK.
func _check(result: Dictionary, action: String) -> bool:
	var status: Dictionary = result.status
	if status.code == STATUS_OK:
		return true
	_log("could not %s: %s (%s)" % [action, status.message, _status_name(status.code)], true)
	return false


## After a failure the host has either kept its session or closed it; a reset tells them apart.
func _resume_manual(message: String) -> void:
	_set_mode(Mode.MANUAL)
	var result := _reset_episode()
	if result.status.code != STATUS_OK:
		_check(result, "reset")
		_close_mode("the training host closed its session")
		return
	_log(message)


func _close_mode(reason: String) -> void:
	_kill_trainer()
	_clear_policy()
	_set_mode(Mode.CLOSED)
	_log("%s; press Reload to reload the scene" % reason, true)
	if quit_after_training:
		get_tree().quit(1)


# --- Training requests ------------------------------------------------------------------------


func _handle_request(request: Dictionary) -> void:
	match request.kind:
		"start":
			if request.autoreset_mode != AUTORESET_NAMES[AUTORESET_DISABLED]:
				connector.fail("INCOMPATIBLE", "This scene's training host session uses DISABLED auto-reset; Python asked for %s." % request.autoreset_mode)
				return
			connector.reply_start()
			connector.publish_definition(definition)
		"reset":
			var settings: Dictionary = request.environments.get(ENVIRONMENT_ID, {})
			var options := {}
			var given_options: Variant = settings.get("options", {})
			if typeof(given_options) == TYPE_DICTIONARY:
				for key in given_options:
					options[str(key)] = str(given_options[key])
			var seed: Variant = settings.get("seed")
			if seed != null:
				seed = int(seed)
			var result := _reset_episode(seed, options)
			if result.status.code != STATUS_OK:
				_fail_request(result, "Reset")
				return
			var state: Dictionary = result.value[ENVIRONMENT_ID][agent_id]
			connector.reply_reset({str(ENVIRONMENT_ID): {agent_id: {
				"observation": ScholaLocalConnector.to_json_value(state.observation),
				"info": state.info,
			}}})
		"step":
			var actions: Dictionary = request.actions[ENVIRONMENT_ID]
			if not actions.has(agent_id):
				connector.fail("INVALID_ARGUMENT", "The step has no action for agent %s." % agent_id)
				return
			var action: Variant = from_json_value(actions[agent_id])
			# A failed host step closes the whole session, so reject a bad action here first.
			var action_error: String = agent.action_space.get_validation_error(action)
			if action_error != "":
				connector.fail("INVALID_ARGUMENT", "Action %s rejected by %s: %s" % [JSON.stringify(actions[agent_id]), agent.action_space.describe(), action_error])
				return
			var result := _step(action, "Python trainer")
			if result.status.code != STATUS_OK:
				_fail_request(result, "Step")
				return
			var state: Dictionary = result.value.state[ENVIRONMENT_ID][agent_id]
			connector.reply_step([{agent_id: {
				"observation": ScholaLocalConnector.to_json_value(state.observation),
				"reward": state.reward,
				"terminated": state.terminated,
				"truncated": state.truncated,
				"info": state.info,
			}}])


func _fail_request(result: Dictionary, what: String) -> void:
	var status: Dictionary = result.status
	connector.fail(_status_name(status.code), "%s failed: %s" % [what, status.message])


## JSON numbers arrive as floats; whole numbers become ints so Discrete, MultiDiscrete and
## MultiBinary actions convert.
static func from_json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			if is_finite(value) and value == floorf(value) and absf(value) < 9007199254740992.0:
				return int(value)
		TYPE_ARRAY:
			var converted := []
			for item in value:
				converted.append(from_json_value(item))
			return converted
		TYPE_DICTIONARY:
			var converted := {}
			for key in value:
				converted[key] = from_json_value(value[key])
			return converted
	return value


func _on_connection_state_changed(state: ScholaLocalConnector.State, message: String) -> void:
	_set_connection_state(state, message)
	match state:
		ScholaLocalConnector.State.WAITING:
			_set_mode(Mode.WAITING)
		ScholaLocalConnector.State.CONNECTED, ScholaLocalConnector.State.TRAINING:
			if mode != Mode.STOPPING:
				_set_mode(Mode.TRAINING)
		ScholaLocalConnector.State.CLOSED, ScholaLocalConnector.State.ERROR:
			_end_training_session(state == ScholaLocalConnector.State.ERROR)


func _on_trainer_notification(message: Dictionary) -> void:
	match message.get("type"):
		"progress":
			trainer_progress.emit(message)
		"saved":
			_log("trainer saved policy to %s" % message.get("path"))
			if policy != null and environment.has_method("record_policy_map"):
				environment.call("record_policy_map", policy.model_path)
		"log":
			_log("python: %s" % message.get("message"))


func _end_training_session(failed: bool) -> void:
	if mode != Mode.WAITING and mode != Mode.TRAINING and mode != Mode.STOPPING:
		return
	if failed:
		_kill_trainer()
	_resume_manual("training session ended; keyboard controls the agent")
	if quit_after_training:
		get_tree().quit(1 if failed else 0)


func _set_connection_state(state: ScholaLocalConnector.State, message: String) -> void:
	connection_state = state
	connection_state_changed.emit(state, message)
	var is_error := state == ScholaLocalConnector.State.ERROR
	_log("connection %s: %s" % [ScholaLocalConnector.STATE_NAMES[state], message], is_error)


func _clear_policy() -> void:
	_policy_state = null
	policy_source = ""


func _kill_trainer() -> void:
	if _pid != -1 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_reset_timer = 0.0
	_viewer_dirty = true
	mode_changed.emit(mode)


## Sends this instance's state to the parallel viewer at most once per frame, and handles the
## viewer's "stop" command, which asks the trainer to save and end the run.
func _report_to_viewer() -> void:
	if _viewer == null:
		return
	while _viewer.get_available_packet_count() > 0:
		if _viewer.get_packet().get_string_from_utf8() == "stop" and mode == Mode.TRAINING:
			_log("the parallel viewer asked to stop")
			stop_run()
	if not _viewer_dirty:
		return
	_viewer_dirty = false
	var report := {
		"port": port,
		"mode": Mode.keys()[mode],
		"episode": episode,
		"step": environment.get_episode_step(),
		"reward": cumulative_reward,
		"outcome": outcome,
		"steps": _total_steps,
		"finished": _finished_episodes,
		"progress": _last_progress,
	}
	if environment.has_method("get_view_state"):
		report["view"] = environment.call("get_view_state")
	_finished_episodes = []
	_viewer.put_packet(JSON.stringify(report).to_utf8_buffer())


static func _status_name(code: int) -> String:
	return STATUS_NAMES[code] if code >= 0 and code < STATUS_NAMES.size() else "UNKNOWN"


func _log(text: String, is_error := false, warn := true) -> void:
	log_message.emit(text, is_error)
	if is_error and warn:
		push_warning("Schola D3: " + text)
	else:
		print("Schola D3: " + text)
