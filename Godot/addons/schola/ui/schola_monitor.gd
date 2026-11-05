# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaMonitor
extends PanelContainer
## Main-thread display API for episode telemetry. Does not step or reset environments.
## Feed begin_episode(), record_step(), and end_episode() from your lifecycle owner.

@export var title: String = "Environment monitor":
	set(value):
		title = value
		if is_instance_valid(_heading):
			_heading.text = value
@export_range(8, 512) var history_limit: int = 120

var episode: int = 0
var step: int = 0
var episode_return: float = 0.0
var agent_returns: Dictionary = {}
var _active: bool = false
var _step_limit: int = 0
var _history: Array[float] = []
var _last_rewards: Dictionary = {}
var _heading: Label
var _status: Label
var _episode_value: Label
var _step_value: Label
var _return_value: Label
var _progress: ProgressBar
var _agents: Tree
var _chart: Control
var _empty: Label


func _ready() -> void:
	custom_minimum_size = Vector2(300, 380)
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("171d28")
	surface.border_color = Color("ed1c24")
	surface.border_width_top = 3
	surface.set_corner_radius_all(10)
	surface.content_margin_left = 18
	surface.content_margin_right = 18
	surface.content_margin_top = 18
	surface.content_margin_bottom = 18
	add_theme_stylebox_override("panel", surface)
	add_theme_color_override("font_color", Color("eef2fa"))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	var brand := Label.new()
	brand.text = "AMD  /  SCHOLA"
	brand.add_theme_font_size_override("font_size", 12)
	brand.add_theme_color_override("font_color", Color("a6b5cc"))
	layout.add_child(brand)
	_heading = Label.new()
	_heading.text = title
	_heading.add_theme_font_size_override("font_size", 22)
	layout.add_child(_heading)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)
	var metrics := HBoxContainer.new()
	layout.add_child(metrics)
	_episode_value = _metric(metrics, "EPISODE")
	_step_value = _metric(metrics, "STEP")
	_return_value = _metric(metrics, "TOTAL RETURN")
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 6
	layout.add_child(_progress)
	_empty = Label.new()
	_empty.text = "Waiting for episode data."
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_empty)
	_chart = Control.new()
	_chart.custom_minimum_size.y = 72
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart.tooltip_text = "Recent cumulative episode return across all agents"
	_chart.draw.connect(_draw_history)
	layout.add_child(_chart)
	_agents = Tree.new()
	_agents.columns = 4
	_agents.hide_root = true
	_agents.column_titles_visible = true
	_agents.custom_minimum_size.y = 100
	_agents.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index in range(4):
		_agents.set_column_title(index, ["Agent", "Reward", "Return", "State"][index])
	layout.add_child(_agents)
	_refresh()


func _metric(parent: Control, caption: String) -> Label:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("a6b5cc"))
	column.add_child(label)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 22)
	column.add_child(value)
	return value


## Start a new display episode; step_limit == 0 means no configured limit.
func begin_episode(number: int, agent_ids: PackedStringArray, step_limit: int = 0) -> void:
	episode = number
	step = 0
	episode_return = 0.0
	_step_limit = maxi(0, step_limit)
	_active = true
	agent_returns.clear()
	_last_rewards.clear()
	_history.assign([0.0])
	for agent_id in agent_ids:
		agent_returns[agent_id] = 0.0
	_refresh()


## Call once per environment step, with each agent's incremental reward.
func record_step(rewards: Dictionary) -> void:
	if not _active:
		return
	# Validate the whole batch before changing any displayed totals.
	for agent_id in rewards:
		if not agent_returns.has(agent_id) or not (rewards[agent_id] is float or rewards[agent_id] is int):
			push_warning("ScholaMonitor: reward batch contains an unknown agent or nonnumeric reward.")
			return
		if not is_finite(float(rewards[agent_id])):
			push_warning("ScholaMonitor: rewards must be finite.")
			return
	step += 1
	_last_rewards = rewards.duplicate()
	for agent_id in rewards:
		agent_returns[agent_id] += float(rewards[agent_id])
		episode_return += float(rewards[agent_id])
	_history.append(episode_return)
	while _history.size() > maxi(8, history_limit):
		_history.pop_front()
	_refresh()


## Use terminated for natural episode endings, truncated for external limits.
func end_episode(truncated: bool = false) -> void:
	if not _active:
		return
	_active = false
	_refresh()
	if is_instance_valid(_status):
		_status.text = "Truncated · external limit" if truncated else "Terminated · episode ended"


func is_episode_active() -> bool:
	return _active


func _refresh() -> void:
	if not is_instance_valid(_status):
		return
	_status.text = "Receiving episode data" if _active else "Idle · no active episode"
	_status.add_theme_color_override("font_color", Color("65dec4") if _active else Color("a6b5cc"))
	_episode_value.text = str(episode) if episode > 0 else "—"
	_step_value.text = "%d / %d" % [step, _step_limit] if _step_limit > 0 else str(step)
	_return_value.text = "%+.3f" % episode_return
	_progress.max_value = maxf(1, _step_limit)
	_progress.value = step if _step_limit > 0 else 0
	_progress.tooltip_text = "Episode step limit" if _step_limit > 0 else "No configured step limit"
	_empty.visible = agent_returns.is_empty()
	_agents.clear()
	var root := _agents.create_item()
	for agent_id in agent_returns:
		var row := _agents.create_item(root)
		row.set_text(0, str(agent_id))
		row.set_text(1, "%+.3f" % float(_last_rewards[agent_id]) if _last_rewards.has(agent_id) else "—")
		row.set_text(2, "%+.3f" % float(agent_returns[agent_id]))
		row.set_text(3, "Active" if _active else "Ended")
	_chart.queue_redraw()


func _draw_history() -> void:
	var area := _chart.size
	_chart.draw_line(Vector2(0, area.y - 1), Vector2(area.x, area.y - 1), Color("344157"))
	if _history.size() < 2:
		return
	var low: float = minf(0, _history.min())
	var high: float = maxf(0.001, _history.max())
	var points := PackedVector2Array()
	for index in range(_history.size()):
		points.append(Vector2(
			float(index) / (_history.size() - 1) * area.x,
			area.y - 4 - (_history[index] - low) / (high - low) * (area.y - 8)))
	_chart.draw_polyline(points, Color("65dec4"), 2, true)
