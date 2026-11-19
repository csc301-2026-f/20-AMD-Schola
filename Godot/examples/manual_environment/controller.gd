# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends Node

const AUTORESET_DISABLED := 2
const Monitor := preload("res://addons/schola/ui/schola_monitor.gd")
const ManualEnvironment := preload("res://examples/manual_environment/environment.gd")

var monitor: ScholaMonitor
var last_result: Dictionary
var episode_done := true
var _session_failed := false
var _reset_button: Button
var _output: Label
var _board: Label
var _seed: SpinBox
var _random_start: CheckBox
var _action_buttons: Array[Button] = []

@onready var host: ScholaTrainingHost = $Host


func _ready() -> void:
	_build_ui()
	_update_buttons()
	# Godot assigns current_scene after adding the scene and running _ready().
	_initialize.call_deferred()


func _initialize() -> void:
	for operation in [host.initialize_session, host.set_autoreset_mode.bind(AUTORESET_DISABLED), host.define]:
		var result: Dictionary = operation.call()
		if not _show_result(result):
			return
	reset_episode()


func reset_episode(seed: Variant = null, options: Dictionary = {}) -> Dictionary:
	if _session_failed:
		return last_result
	var settings := {"options": options}
	if seed != null:
		settings["seed"] = seed
	var result := host.reset({0: settings})
	if _show_result(result):
		episode_done = false
		monitor.begin_episode(monitor.episode + 1, PackedStringArray(["walker"]), ManualEnvironment.STEP_LIMIT)
		_update_board(int(result["value"][0]["walker"]["observation"]))
	_update_buttons()
	return result


func submit_action(action: Variant) -> Dictionary:
	if _session_failed:
		return last_result
	var result := host.step({"actions": [{"walker": action}]})
	if _show_result(result):
		var state: Dictionary = result["value"]["state"][0]["walker"]
		# A disabled-autoreset host can return retained terminal state. Count it once.
		if not episode_done:
			monitor.record_step({"walker": state["reward"]})
			if state["terminated"] or state["truncated"]:
				monitor.end_episode(state["truncated"])
		episode_done = state["terminated"] or state["truncated"]
		_update_board(int(state["observation"]))
	_update_buttons()
	return result


func _show_result(result: Dictionary) -> bool:
	last_result = result
	_output.text = str(result)
	var succeeded: bool = result["status"]["code"] == 0
	if not succeeded and not host.is_session_active():
		_session_failed = true
		episode_done = true
		monitor.stop_episode()
		_board.text = "Session stopped after an error. Fix the error. Restart the scene."
		_update_buttons()
	return succeeded


func _update_board(position: int) -> void:
	var cells: PackedStringArray = []
	for index in range(5):
		cells.append("[You]" if index == position else ("[Goal]" if index == 4 else "[   ]"))
	_board.text = "   ".join(cells)
	if episode_done:
		_board.text += "\nEpisode complete. Reset to continue."


func _update_buttons() -> void:
	_reset_button.disabled = _session_failed
	for button in _action_buttons:
		button.disabled = episode_done


func _reset_from_ui() -> void:
	reset_episode(int(_seed.value), {"start": "random" if _random_start.button_pressed else "fixed"})


func _input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.is_pressed():
		return
	# Let text fields retain cursor navigation and editing shortcuts.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	if event.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_R]:
		return
	# Handle movement before the GUI uses arrows to move control focus.
	get_viewport().set_input_as_handled()
	if event.is_echo():
		return
	if event.keycode == KEY_R:
		_reset_from_ui()
	elif not episode_done and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		submit_action(0 if event.keycode == KEY_LEFT else 1)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0c111a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	scroll.add_child(row)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size.x = 440
	column.add_theme_constant_override("separation", 16)
	row.add_child(column)
	var title := Label.new()
	title.text = "Schola / Manual environment"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var instructions := Label.new()
	instructions.text = "No Python or training connection.\nLeft / Right: one step. R: reset.\nReach the goal within 8 steps.\nReward: +1 at goal, -0.01 otherwise.\nReset does not happen automatically."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(instructions)
	_board = Label.new()
	_board.add_theme_font_size_override("font_size", 26)
	column.add_child(_board)
	var controls := HFlowContainer.new()
	column.add_child(controls)
	for action in range(2):
		var button := Button.new()
		button.text = "Left" if action == 0 else "Right"
		button.pressed.connect(submit_action.bind(action))
		controls.add_child(button)
		_action_buttons.append(button)
	_reset_button = Button.new()
	_reset_button.text = "Reset"
	_reset_button.pressed.connect(_reset_from_ui)
	controls.add_child(_reset_button)
	_seed = SpinBox.new()
	_seed.min_value = -2147483648
	_seed.max_value = 2147483647
	_seed.value = 42
	_seed.tooltip_text = "Reset seed (signed 32-bit integer)"
	controls.add_child(_seed)
	_random_start = CheckBox.new()
	_random_start.text = "Random start"
	controls.add_child(_random_start)
	_output = Label.new()
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_output)
	monitor = Monitor.new()
	monitor.title = "Live episode"
	monitor.custom_minimum_size.x = 360
	monitor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(monitor)
