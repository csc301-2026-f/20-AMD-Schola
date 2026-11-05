@tool
@icon("res://addons/schola_d3/icons/schola_environment.svg")
class_name GridEnvironment
extends ScholaEnvironment
## The grid world as a native Schola environment. ScholaTrainingHost (US4) runs these hooks through
## the US1 environment adapter, which also seeds get_rng() and counts episode steps.

const RUNNING := "running"
const SUCCESS := "success"
const FAILURE := "failure"
const TIMEOUT := "timeout"

@export_group("Episode")
## Truncates the episode after this many steps; 0 disables the limit. Implemented in _is_truncated()
## rather than a separate node, as US5 specifies.
@export_range(0, 1000) var max_episode_steps := 40
@export_group("Rewards")
@export var goal_reward := 10.0
@export var failure_penalty := -10.0
@export var step_penalty := -0.1
@export_group("Start")
@export var random_start := true
@export var start_cell := Vector2i(0, 5)

@onready var arena := $Arena as GridArena


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	# The adapter has already applied the seed to get_rng(), so every random draw comes from there.
	for agent in get_agents():
		var cell := arena.random_free_cell(get_rng()) if random_start else start_cell
		(agent as GridAgent).player.place(cell)


func _get_reward(agent: ScholaAgent) -> float:
	var kind := _cell_kind(agent)
	if kind == GridArena.GOAL:
		return step_penalty + goal_reward
	if kind == GridArena.HAZARD:
		return step_penalty + failure_penalty
	return step_penalty


func _is_terminated(agent: ScholaAgent) -> bool:
	return _cell_kind(agent) != GridArena.FLOOR


func _is_truncated(agent: ScholaAgent) -> bool:
	# The current step is not counted yet while the hooks run.
	return max_episode_steps > 0 and get_episode_step() + 1 >= max_episode_steps and not _is_terminated(agent)


func _get_info(agent: ScholaAgent) -> Dictionary:
	return {"outcome": get_outcome(agent)}


func get_outcome(agent: ScholaAgent) -> String:
	var kind := _cell_kind(agent)
	if kind == GridArena.GOAL:
		return SUCCESS
	if kind == GridArena.HAZARD:
		return FAILURE
	if _is_truncated(agent):
		return TIMEOUT
	return RUNNING


func get_config() -> Dictionary:
	return {
		"max_episode_steps": max_episode_steps,
		"goal_reward": goal_reward,
		"failure_penalty": failure_penalty,
		"step_penalty": step_penalty,
	}


## A small snapshot of the board for the parallel viewer.
func get_view_state() -> Dictionary:
	var agents := []
	for agent in get_agents():
		var cell: Vector2i = (agent as GridAgent).player.cell
		agents.append([cell.x, cell.y])
	var hazards := []
	for cell in arena.get_hazard_cells():
		hazards.append([cell.x, cell.y])
	var goal := arena.get_goal_cell()
	return {
		"size": [arena.grid_size.x, arena.grid_size.y],
		"goal": [goal.x, goal.y],
		"hazards": hazards,
		"agents": agents,
	}


func _cell_kind(agent: ScholaAgent) -> String:
	return arena.get_cell_kind((agent as GridAgent).player.cell)
