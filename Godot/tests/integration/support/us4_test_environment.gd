# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends ScholaEnvironment

var reset_count := 0
var episode_length := 2
var last_seed: Variant
var last_options: Dictionary


func _reset_episode(seed: Variant, options: Dictionary) -> void:
	last_seed = seed
	last_options = options
	reset_count += 1
	for agent in get_agents():
		agent.observation = 0


func _get_reward(_agent: ScholaAgent) -> float:
	return 1.0


func _is_terminated(_agent: ScholaAgent) -> bool:
	return get_episode_step() + 1 >= episode_length


func _get_info(_agent: ScholaAgent) -> Dictionary:
	return {"reset_count": str(reset_count)}
