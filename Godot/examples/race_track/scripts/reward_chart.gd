# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Control

const STEPS_PER_POINT := 256
const SMOOTHING := 0.1
const PLOT := Rect2(16.0, 44.0, 208.0, 64.0)
const LINE := Color(0.3, 0.85, 0.4)
const MUTED := Color(1.0, 1.0, 1.0, 0.7)
const BASELINE := Color(1.0, 1.0, 1.0, 0.25)
const PANEL: StyleBoxFlat = preload("res://examples/race_track/scenes/hud_panel.tres")

@export var environment_path: NodePath
@onready var environment: RaceTrackEnvironment = get_node(environment_path)
var points := PackedFloat32Array()
var _steps := 0
var _reward := 0.0


func _ready() -> void:
	visible = not RaceTrackEnvironment.is_test_drive()
	environment.step_rewarded.connect(_on_step_rewarded)


func _on_step_rewarded(reward: float) -> void:
	_steps += 1
	_reward += reward
	if _steps % STEPS_PER_POINT != 0:
		return
	var per_second := _reward / STEPS_PER_POINT * Engine.physics_ticks_per_second
	points.append(per_second if points.is_empty() else lerpf(points[-1], per_second, SMOOTHING))
	_reward = 0.0
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_style_box(PANEL, Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(14.0, 26.0), "REWARD PER SECOND", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)
	var lowest := 0.0
	var highest := 1.0
	for point in points:
		lowest = minf(lowest, point)
		highest = maxf(highest, point)
	var zero := remap(0.0, lowest, highest, PLOT.end.y, PLOT.position.y)
	draw_line(Vector2(PLOT.position.x, zero), Vector2(PLOT.end.x, zero), BASELINE, 1.0)
	draw_string(font, Vector2(PLOT.position.x, 128.0), "0", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, MUTED)
	draw_string(font, Vector2(PLOT.position.x, 128.0), "%d steps" % _steps, HORIZONTAL_ALIGNMENT_RIGHT, PLOT.size.x, 12, MUTED)
	if points.is_empty():
		return
	draw_string(font, Vector2(PLOT.position.x, 26.0), "%.1f" % points[-1], HORIZONTAL_ALIGNMENT_RIGHT, PLOT.size.x, 16)
	var line := PackedVector2Array()
	for index in points.size():
		var along := index / maxf(points.size() - 1.0, 1.0)
		line.append(Vector2(lerpf(PLOT.position.x, PLOT.end.x, along), remap(points[index], lowest, highest, PLOT.end.y, PLOT.position.y)))
	if line.size() > 1:
		draw_polyline(line, LINE, 2.0, true)
	draw_circle(line[-1], 4.0, LINE)
