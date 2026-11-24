# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends RaceTrackEditorTrainer

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
	return PackedStringArray([
		"-X", "utf8", "-u", "-c", "from schola.scripts.launch import main; main()",
		"rllib", "train", "ppo",
		"--timesteps", str(steps),
		"--fcnet-hiddens", "64", "64",
		"--train-batch-size-per-learner", "2048",
		"--learning-rate", "0.0003",
		"editor", "--url", "127.0.0.1", "--port", "8000",
	])
