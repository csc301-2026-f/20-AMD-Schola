# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Control

const GAS := Color(0.3, 0.85, 0.4)
const BRAKE := Color(0.95, 0.3, 0.25)
const MARK := Color(1.0, 0.7, 0.2)
const EMPTY := Color(1.0, 1.0, 1.0, 0.15)
const MUTED := Color(1.0, 1.0, 1.0, 0.7)

@export var controls_path: NodePath
@onready var controls: RaceTrackControls = get_node(controls_path)
@onready var car: VehicleBody3D = controls.get_node(controls.body_path)
var panel := StyleBoxFlat.new()


func _ready() -> void:
	panel.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	panel.set_corner_radius_all(10)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var steering := clampf(controls.action[0], -1.0, 1.0)
	var pedal := clampf(controls.action[1], -1.0, 1.0)
	var font := get_theme_default_font()
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(14.0, 26.0), "AGENT ACTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, MUTED)
	var center := Vector2(62.0, 84.0)
	var turn := steering * PI * 0.5
	draw_arc(center, 34.0, 0.0, TAU, 48, Color.WHITE, 7.0, true)
	draw_arc(center, 34.0, turn - PI * 0.5 - 0.25, turn - PI * 0.5 + 0.25, 8, MARK, 7.0, true)
	for spoke in [0.0, PI * 0.5, PI]:
		draw_line(center, center + Vector2.from_angle(spoke + turn) * 32.0, Color.WHITE, 5.0, true)
	draw_circle(center, 9.0, Color.WHITE)
	var percent := roundi(absf(steering) * 100.0)
	var direction := "" if percent == 0 else ("LEFT " if steering < 0.0 else "RIGHT ")
	_label(font, 62.0, "STEER", direction + "%d%%" % percent)
	_pedal(font, 140.0, maxf(-pedal, 0.0), BRAKE, "BRAKE")
	_pedal(font, 192.0, maxf(pedal, 0.0), GAS, "GAS")
	draw_line(Vector2(222.0, 46.0), Vector2(222.0, 166.0), EMPTY, 2.0)
	draw_string(font, Vector2(222.0, 100.0), str(roundi(car.linear_velocity.length() * 3.6)), HORIZONTAL_ALIGNMENT_CENTER, 78.0, 34)
	_label(font, 261.0, "SPEED", "km/h")


func _pedal(font: Font, x: float, amount: float, color: Color, title: String) -> void:
	draw_rect(Rect2(x - 15.0, 46.0, 30.0, 76.0), EMPTY)
	draw_rect(Rect2(x - 15.0, 122.0 - 76.0 * amount, 30.0, 76.0 * amount), color)
	_label(font, x, title, "%d%%" % roundi(amount * 100.0))


func _label(font: Font, x: float, title: String, value: String) -> void:
	draw_string(font, Vector2(x - 50.0, 144.0), title, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 12, MUTED)
	draw_string(font, Vector2(x - 50.0, 162.0), value, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 14)
