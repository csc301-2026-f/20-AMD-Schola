# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackEditorTrainer
extends Node

const TRAIN_SCRIPT := "res://examples/race_track/train.py"
const SAVED_MODEL := "res://examples/race_track/policies/race_track.zip"

@export var steps := 100000

var _pid := 0
var _pipes: Array[FileAccess] = []
var _partial_lines: Array[String] = []


func _ready() -> void:
	if not OS.has_feature("editor") or not OS.get_cmdline_user_args().is_empty() or get_tree().current_scene != owner:
		return
	var python := _find_python()
	var arguments := PackedStringArray(["-u", ProjectSettings.globalize_path(TRAIN_SCRIPT), "--godot", OS.get_executable_path(), "--attach", "--steps", str(steps)])
	if FileAccess.file_exists(SAVED_MODEL):
		arguments.append("--resume")
	var process := OS.execute_with_pipe(python, arguments, false)
	if process.is_empty():
		push_error("Could not start %s %s" % [python, " ".join(arguments)])
		return
	_pid = process.pid
	_pipes = [process.stdio, process.stderr]
	_partial_lines = ["", ""]
	print("Started training with %s" % python)


func _process(_delta: float) -> void:
	for index in _pipes.size():
		var text := _pipes[index].get_buffer(65536).get_string_from_utf8()
		if text.is_empty():
			continue
		var lines := (_partial_lines[index] + text).split("\n")
		_partial_lines[index] = lines[-1]
		for line in lines.slice(0, -1):
			if index == 0:
				print(line.trim_suffix("\r"))
			else:
				printerr(line.trim_suffix("\r"))


func _exit_tree() -> void:
	if _pid == 0 or not OS.is_process_running(_pid):
		return
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/T", "/F", "/PID", str(_pid)])
	else:
		OS.kill(_pid)


func _find_python() -> String:
	var project := ProjectSettings.globalize_path("res://")
	for venv in [".venv", "../.venv", "../venv"]:
		for executable in ["Scripts/python.exe", "bin/python"]:
			var path := project.path_join(venv).path_join(executable).simplify_path()
			if FileAccess.file_exists(path):
				return path
	return "python"
