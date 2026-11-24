# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Node

const AHEAD := 50.0
const SPACING := 40.0
const CLEAR_AHEAD := 40.0
const CLEAR_BEHIND := 10.0
const PAINTS: Array[Color] = [Color(0.1, 0.45, 1.0), Color(0.95, 0.95, 0.95), Color(0.55, 0.2, 0.9), Color(0.1, 0.75, 0.7)]

@export var car_scene: PackedScene
@export var agent_path: NodePath
@export var stepper_paths: Array[NodePath] = []

@onready var agent: RaceTrackAgent = get_node(agent_path)
var added: Array[RaceTrackAgent] = []
var _keys: Array[Key] = []


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo:
		_keys.append(key.keycode)


func _physics_process(_delta: float) -> void:
	for key in _keys:
		match key:
			KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
				add()
			KEY_MINUS, KEY_KP_SUBTRACT:
				remove()
			KEY_R:
				restart()
	_keys.clear()


func add() -> void:
	var offset := _clear_offset(added)
	if offset < 0.0:
		return
	var car: VehicleBody3D = car_scene.instantiate()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = PAINTS[added.size() % PAINTS.size()]
	for part in ["Body", "Cabin"]:
		car.get_node(part).material_override = paint
	add_child(car)
	var added_agent: RaceTrackAgent = car.get_node("Agent")
	added_agent.rays.draw_debug = agent.rays.draw_debug
	added_agent.place(agent.track.transform_at(offset))
	for path in stepper_paths:
		(get_node(path) as ScholaInferenceStepper).add_agent(added_agent)
	added.append(added_agent)


func remove() -> void:
	if not added.is_empty():
		var last: RaceTrackAgent = added.pop_back()
		last.car.queue_free()


func restart() -> void:
	for index in added.size():
		var offset := _clear_offset(added.slice(0, index))
		if offset >= 0.0:
			added[index].place(agent.track.transform_at(offset))


func _clear_offset(others: Array[RaceTrackAgent]) -> float:
	var track := agent.track
	var length := track.curve.get_baked_length()
	var here := track.progress_of(agent.car.global_position)
	for step in floori(length - AHEAD - SPACING):
		var offset := fposmod(here + AHEAD + step, length)
		if _is_clear(offset, others):
			return offset
	return -1.0


func _is_clear(offset: float, others: Array[RaceTrackAgent]) -> bool:
	var track := agent.track
	var length := track.curve.get_baked_length()
	if not track.is_clear(offset):
		return false
	for body in get_tree().get_nodes_in_group("obstacle"):
		var ahead := fposmod(body.get_meta("track_offset", 0.0) - offset, length)
		if body.visible and (ahead < CLEAR_AHEAD or ahead > length - CLEAR_BEHIND):
			return false
	for other in others:
		if absf(wrapf(track.progress_of(other.car.global_position) - offset, -length * 0.5, length * 0.5)) < SPACING:
			return false
	return true
