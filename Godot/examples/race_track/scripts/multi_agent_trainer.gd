# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends RaceTrackEditorTrainer

const MULTI_AGENT_SCRIPT := "res://examples/race_track/train_multi_agent.py"

@export var pretrained := false

var _reader := Thread.new()
var _reading := true


func _ready() -> void:
	super()
	if _pid != 0:
		_reader.start(_read)


func _process(_delta: float) -> void:
	pass


func _read() -> void:
	while _reading:
		super._process(0.0)
		OS.delay_msec(20)


func _exit_tree() -> void:
	super()
	_reading = false
	if _reader.is_started():
		_reader.wait_to_finish()


func _arguments() -> PackedStringArray:
	var arguments := PackedStringArray(["-X", "utf8", "-u", ProjectSettings.globalize_path(MULTI_AGENT_SCRIPT), "--steps", str(steps)])
	if pretrained:
		arguments.append("--pretrained")
	return arguments
