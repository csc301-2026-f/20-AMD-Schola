# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends ScholaEnvironment

var reset_count := 0
var episode_length := 2
var last_seed: Variant
var last_options: Dictionary
var on_step_result: Callable
var on_reset: Callable


func _reset_episode(seed: Variant, options: Dictionary) -> void:
	last_seed = seed
	last_options = options
	reset_count += 1
	if on_reset.is_valid():
		on_reset.call()
	for agent in get_agents():
		agent.observation = 0


func _get_step_result(_agent: ScholaAgent) -> Dictionary:
	if on_step_result.is_valid():
		on_step_result.call(_agent)
	return {
		"reward": 1.0,
		"terminated": get_episode_step() + 1 >= episode_length,
		"info": {"reset_count": str(reset_count)},
	}
