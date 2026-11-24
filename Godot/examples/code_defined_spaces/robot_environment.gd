# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends ScholaEnvironment

@export_range(1, 100) var episode_steps := 3


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	$Robot.reset_sample()


func _get_step_result(_agent: ScholaAgent) -> Dictionary:
	return {
		"reward": 1.0,
		"terminated": false,
		"truncated": get_episode_step() + 1 >= episode_steps,
	}
