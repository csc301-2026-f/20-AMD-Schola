# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends ScholaEnvironment

const GOAL := 4
const STEP_LIMIT := 8

var last_seed: Variant
var last_options: Dictionary


func _reset_episode(seed: Variant, options: Dictionary) -> void:
	last_seed = seed
	last_options = options.duplicate()
	var start := 0
	if options.get("start", "fixed") == "random":
		var rng := RandomNumberGenerator.new()
		if seed == null:
			rng.randomize()
		else:
			rng.seed = int(seed)
		start = rng.randi_range(0, GOAL - 1)
	$Agent.position = start


func _get_step_result(agent: ScholaAgent) -> Dictionary:
	var reached_goal: bool = agent.position == GOAL
	return {
		"reward": 1.0 if reached_goal else -0.01,
		"terminated": reached_goal,
		"truncated": not reached_goal and get_episode_step() + 1 >= STEP_LIMIT,
		"info": {"goal": str(GOAL), "step": str(get_episode_step() + 1)},
	}
