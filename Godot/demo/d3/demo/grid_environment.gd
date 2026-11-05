# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

@tool
@icon("res://addons/schola_d3/icons/schola_environment.svg")
class_name GridEnvironment
extends ScholaEnvironment
## The grid world as a native Schola environment. ScholaTrainingHost (US4) runs these hooks through
## the US1 environment adapter, which also seeds get_rng() and counts episode steps.
##
## The map comes from the scene's markers unless a saved map exists (MAP_PATH, or --map=<file> on
## the command line). Every parallel-training instance reads the same saved map. The observation
## space follows the map size, so a map change takes effect when the scene loads.

const RUNNING := "running"
const SUCCESS := "success"
const FAILURE := "failure"
const TIMEOUT := "timeout"
const MAP_PATH := "user://d3_map.json"

@export_group("Episode")
## Truncates the episode after this many steps; 0 disables the limit. Implemented in _get_step_result()
## rather than a separate node, as US5 specifies.
@export_range(0, 1000) var max_episode_steps := 40
@export_group("Rewards")
@export var goal_reward := 10.0
@export var failure_penalty := -10.0
@export var step_penalty := -0.1
@export_group("Start")
@export var random_start := true
@export var start_cell := Vector2i(0, 5)
@export_group("Map")
## Load the saved map on start. Tests turn this off to use the scene's map.
@export var use_saved_map := true

@onready var arena := $Arena as GridArena

## The map authored in the scene.
var default_map := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	default_map = arena.get_map()
	if use_saved_map:
		var map := load_saved_map()
		if not map.is_empty():
			var error := GridArena.validate_map(map)
			if error == "":
				arena.apply_map(map)
			else:
				push_warning("Ignoring the saved map %s: %s" % [saved_map_path(), error])
	_update_observation_space()


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	# The adapter has already applied the seed to get_rng(), so every random draw comes from there.
	for agent in get_agents():
		var cell := arena.random_free_cell(get_rng()) if random_start else _fixed_start_cell()
		(agent as GridAgent).player.place(cell)


func _get_step_result(agent: ScholaAgent) -> Variant:
	return {
		"reward": _reward(agent),
		"terminated": _reached_end(agent),
		"truncated": _timed_out(agent),
		"info": {"outcome": get_outcome(agent)},
	}


func get_outcome(agent: ScholaAgent) -> String:
	var kind := _cell_kind(agent)
	if kind == GridArena.GOAL:
		return SUCCESS
	if kind == GridArena.HAZARD:
		return FAILURE
	if _timed_out(agent):
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


# --- Map -------------------------------------------------------------------------------------


static func saved_map_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			return arg.get_slice("=", 1)
	return MAP_PATH


static func load_saved_map() -> Dictionary:
	var path := saved_map_path()
	if not FileAccess.file_exists(path):
		return {}
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return map if typeof(map) == TYPE_DICTIONARY else {}


func get_map() -> Dictionary:
	return arena.get_map()


func get_map_summary() -> String:
	var map := arena.get_map()
	var summary := "%d×%d · %d hazard%s" % [map.size[0], map.size[1], map.hazards.size(), "" if map.hazards.size() == 1 else "s"]
	var unreachable := arena.unreachable_cells().size()
	if unreachable > 0:
		summary += " · %d cut off" % unreachable
	return summary


func is_default_map() -> bool:
	return _map_key(arena.get_map()) == _map_key(default_map)


func set_map_editing(editing: bool) -> void:
	arena.set_editing(editing)


func resize_map(dx: int, dy: int) -> void:
	arena.resize_map(Vector2i(dx, dy))


func randomize_map() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	arena.randomize_map(rng)


func restore_default_map() -> void:
	arena.apply_map(default_map)


## Saves the edited map for the next scene load. The default map clears the saved file.
## Returns an error message, or "" on success.
func save_map() -> String:
	var map := arena.get_map()
	var error := GridArena.validate_map(map)
	if error != "":
		return error
	var path := saved_map_path()
	if is_default_map():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(map, " "))
	return ""


## Records which map a policy was trained on, next to the model.
func record_policy_map(model_path: String) -> void:
	var file := FileAccess.open(_policy_map_path(model_path), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(arena.get_map(), " "))


## Returns a warning when the policy was trained on another map, or "" when it matches.
func check_policy_map(model_path: String) -> String:
	var path := _policy_map_path(model_path)
	var trained_on: Variant = default_map
	if FileAccess.file_exists(path):
		trained_on = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(trained_on) == TYPE_DICTIONARY and _map_key(trained_on) == _map_key(arena.get_map()):
		return ""
	return "this policy was trained on a different map; train again for the current map"


func _policy_map_path(model_path: String) -> String:
	return ProjectSettings.globalize_path(model_path.get_basename() + ".map.json")


# Saved maps hold JSON floats, so compare through the same JSON round trip.
static func _map_key(map: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(map)), "", true)


func _update_observation_space() -> void:
	var reach_x := arena.grid_size.x - 1
	var reach_y := arena.grid_size.y - 1
	var space := ScholaBoxSpace.new()
	space.low = PackedFloat32Array([0, 0, -reach_x, -reach_y])
	space.high = PackedFloat32Array([reach_x, reach_y, reach_x, reach_y])
	space.shape = PackedInt32Array([4])
	for agent in get_agents():
		agent.observation_space = space


func _fixed_start_cell() -> Vector2i:
	if start_cell == arena.clamp_cell(start_cell) and arena.get_cell_kind(start_cell) == GridArena.FLOOR:
		return start_cell
	for y in arena.grid_size.y:
		for x in arena.grid_size.x:
			if arena.get_cell_kind(Vector2i(x, y)) == GridArena.FLOOR:
				return Vector2i(x, y)
	return Vector2i.ZERO


func _reward(agent: ScholaAgent) -> float:
	var kind := _cell_kind(agent)
	if kind == GridArena.GOAL:
		return step_penalty + goal_reward
	if kind == GridArena.HAZARD:
		return step_penalty + failure_penalty
	return step_penalty


func _reached_end(agent: ScholaAgent) -> bool:
	return _cell_kind(agent) != GridArena.FLOOR


func _timed_out(agent: ScholaAgent) -> bool:
	# The current step is not counted yet while _get_step_result() runs.
	return max_episode_steps > 0 and get_episode_step() + 1 >= max_episode_steps and not _reached_end(agent)


func _cell_kind(agent: ScholaAgent) -> String:
	return arena.get_cell_kind((agent as GridAgent).player.cell)
