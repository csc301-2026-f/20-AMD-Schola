# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Node

const AUTORESET_DISABLED := 2

@onready var _host: ScholaTrainingHost = $TrainingHost
@onready var _environment: ScholaEnvironment = $Environment
@onready var _agent: ScholaAgent = $Environment/Robot
@onready var _status: Label = $Status


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_status.text = "US15: code-defined spaces\nSynthetic RGB pixels and repeated joints\n\n"
	var succeeded := _run_episodes()
	if not _check("Close", _host.close()):
		succeeded = false
	if succeeded:
		_log("Passed: two episodes, %d actions, each space-definition hook called once." % (
			2 * _environment.episode_steps
		))
	if "--us15-smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit(0 if succeeded else 1)


func _run_episodes() -> bool:
	if not _check("Initialize", _host.initialize_session()):
		return false
	if not _check("Autoreset disabled", _host.set_autoreset_mode(AUTORESET_DISABLED)):
		return false
	var definition := _host.define()
	if not _check("Define", definition):
		return false
	# Keep the console useful: do not print expanded bounds or pixel buffers.
	_log("RGB camera: %d x %d x 3 (%d channel values)" % [
		_agent.camera_width, _agent.camera_height,
		_agent.camera_width * _agent.camera_height * 3,
	])
	_log("Limbs: %d; joints per limb: %d" % [_agent.limb_count, _agent.joints_per_limb])
	for episode in range(2):
		if not _check("Episode %d reset" % (episode + 1), _host.reset({})):
			return false
		for step in range(_environment.episode_steps):
			var actions := {}
			actions[_agent.get_resolved_agent_id()] = _agent.sample_action()
			var result := _host.step({"actions": [actions]})
			if not _check("Episode %d step %d" % [episode + 1, step + 1], result):
				return false
		if _agent.action_count != _environment.episode_steps:
			return _fail("The agent did not receive every action.")
	if _agent.definition_calls != 1:
		return _fail("Expected one observation-space callback, got %d." % _agent.definition_calls)
	if _agent.action_definition_calls != 1:
		return _fail("Expected one action-space callback, got %d." % _agent.action_definition_calls)
	return true


func _check(operation: String, result: Dictionary) -> bool:
	if result.status.code != 0:
		return _fail("%s failed: %s" % [operation, result.status.message])
	_log("%s: OK" % operation)
	return true


func _fail(message: String) -> bool:
	_log(message)
	push_error(message)
	return false


func _log(message: String) -> void:
	print(message)
	_status.text += message + "\n"
