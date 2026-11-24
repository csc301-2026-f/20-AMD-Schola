# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Label

const REVERSE_FORCE := 3000.0
const REVERSE_SPEED := 5.0
const STOPPED := 1.0

@export var agent_path: NodePath
@export var stepper_paths: Array[NodePath] = []

@onready var agent: RaceTrackAgent = get_node(agent_path)
var manual := false
var _switch := false


func _ready() -> void:
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_M:
		_switch = not _switch


func _physics_process(_delta: float) -> void:
	if _switch:
		_switch = false
		set_manual(not manual)
	if manual:
		_drive()


func set_manual(value: bool) -> void:
	manual = value
	visible = value
	for path in stepper_paths:
		var stepper: ScholaInferenceStepper = get_node(path)
		if manual:
			stepper.remove_agent(agent)
		else:
			stepper.add_agent(agent)


func _drive() -> void:
	var steering := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var pedal := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	agent.controls._act(PackedFloat32Array([steering, pedal]))
	var speed := agent.car.linear_velocity.dot(agent.car.global_basis.z)
	if pedal < 0.0 and speed < STOPPED:
		agent.car.brake = 0.0
		agent.car.engine_force = -REVERSE_FORCE if speed > -REVERSE_SPEED else 0.0
	if agent.rays.draw_debug:
		agent.rays._observe()
