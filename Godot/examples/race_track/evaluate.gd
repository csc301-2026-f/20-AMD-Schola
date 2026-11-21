# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
## Scores RaceTrack policies without Python. Each argument is an ONNX path or
## "random" for the seeded random-action baseline. Run with --fixed-fps 60 so a
## 50-second episode finishes in a few seconds.
extends SceneTree

const MODELS: Array[String] = [
	"res://examples/race_track/policies/race_track.onnx",
	RaceTrackEvaluation.RANDOM,
]
const SECONDS := 50.0


func _initialize() -> void:
	await process_frame
	var models: Array = Array(OS.get_cmdline_user_args())
	if models.is_empty():
		models = MODELS
	var failed := false
	for model in models:
		var result: Dictionary = await RaceTrackEvaluation.drive(get_root(), model, SECONDS)
		print(RaceTrackEvaluation.describe(result))
		failed = failed or not result.error.is_empty()
	quit(1 if failed else 0)
