# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Control
## Synthetic telemetry for inspecting the UI. No trainer or environment is running.

const Monitor = preload("res://addons/schola/ui/schola_monitor.gd")
var monitor: ScholaMonitor
var _episode: int = 0
var _sample: int = 0
var _timer: Timer
var _play: Button


func _ready() -> void:
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
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 14)
	scroll.add_child(layout)
	var heading := Label.new()
	heading.text = "Schola  /  Runtime UI"
	heading.add_theme_font_size_override("font_size", 28)
	layout.add_child(heading)
	var note := Label.new()
	note.text = "UI PREVIEW · synthetic rewards, no training connection\nUse the controls to inspect reward updates and episode endings."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("a6b5cc"))
	layout.add_child(note)
	var controls := HFlowContainer.new()
	layout.add_child(controls)
	_button(controls, "New episode", _new_episode)
	_button(controls, "Next step", _next_step)
	_play = _button(controls, "Auto play", _toggle_play)
	_button(controls, "Terminate", func(): _finish(false))
	_button(controls, "Truncate", func(): _finish(true))
	monitor = Monitor.new()
	monitor.title = "Two-agent environment"
	monitor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(monitor)
	_timer = Timer.new()
	_timer.wait_time = 0.25
	_timer.timeout.connect(_next_step)
	add_child(_timer)
	_new_episode()


func _button(parent: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _new_episode() -> void:
	_stop_play()
	_episode += 1
	_sample = 0
	monitor.begin_episode(_episode, PackedStringArray(["Scout", "Runner"]), 60)


func _next_step() -> void:
	if not monitor.is_episode_active():
		return
	_sample += 1
	monitor.record_step({"Scout": sin(_sample * 0.4) * 0.2 + 0.08, "Runner": cos(_sample * 0.3) * 0.15 + 0.04})
	if _sample >= 60:
		_finish(true)


func _toggle_play() -> void:
	if not monitor.is_episode_active():
		return
	if _timer.is_stopped():
		_timer.start()
		_play.text = "Pause preview"
	else:
		_stop_play()


func _stop_play() -> void:
	_timer.stop()
	_play.text = "Auto play"


func _finish(truncated: bool) -> void:
	_stop_play()
	monitor.end_episode(truncated)
