# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Label

const PANEL: StyleBoxFlat = preload("res://examples/race_track/scenes/hud_panel.tres")

@export var stepper_paths: Array[NodePath] = []
@export var names := PackedStringArray()
@export var agent_path: NodePath
@export var selected := 0

@onready var agent: RaceTrackAgent = get_node(agent_path)
var steppers: Array[ScholaInferenceStepper] = []
var _restart := false


func _ready() -> void:
	for path in stepper_paths:
		steppers.append(get_node(path))
	add_theme_stylebox_override("normal", PANEL)
	add_theme_font_size_override("font_size", 14)
	select(selected)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		_restart = true
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + steppers.size():
		select(key.keycode - KEY_1)


func select(index: int) -> void:
	selected = index
	for i in steppers.size():
		steppers[i].enabled = i == index
	text = "AI MODEL: %s" % names[index]


func _physics_process(_delta: float) -> void:
	if _restart:
		_restart = false
		agent.place_at_start()
