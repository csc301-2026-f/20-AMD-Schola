# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# US12: two agents walk a line from 0 to 9 in one environment.
#
# Each agent's episode ends when it reaches 9 (terminated) or when the episode
# hits max_steps (truncated). Agents can finish on different steps: a finished
# agent stops acting, and the episode ends once every agent is done.
#
# reward_mode picks how rewards are shared:
#   "individual": each agent is rewarded for its own progress (+1 forward,
#                 -1 back), plus a bonus on reaching the goal.
#   "shared":     every agent gets the team average, so they succeed together.
extends ScholaEnvironment

const GOAL_BONUS := 5.0
const STEP_COST := 0.05

@export_enum("individual", "shared") var reward_mode := "individual"
@export var max_steps := 40

var episode_count := 0


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	episode_count += 1
	for agent in get_agents():
		agent.position = 0
		agent.previous_position = 0
		agent.acted_on_step = -1


func _get_step_result(agent: ScholaAgent) -> Dictionary:
	var reward := _team_reward() if reward_mode == "shared" else _own_reward(agent)
	var terminated: bool = agent.reached_goal()
	var truncated := not terminated and get_episode_step() + 1 >= max_steps
	return {
		"reward": reward,
		"terminated": terminated,
		"truncated": truncated,
		"info": {
			"agent": agent.get_resolved_agent_id(),
			"position": str(agent.position),
			"episode": str(episode_count),
		},
	}


func _own_reward(agent: ScholaAgent) -> float:
	var reward := float(agent.position - agent.previous_position) - STEP_COST
	if agent.reached_goal():
		reward += GOAL_BONUS
	return reward


# Only agents that acted this step are still in the episode, so only they count
# towards the average.
func _team_reward() -> float:
	var total := 0.0
	var acting := 0
	for agent in get_agents():
		if agent.acted_on_step != get_episode_step():
			continue
		total += _own_reward(agent)
		acting += 1
	return total / acting if acting > 0 else 0.0
