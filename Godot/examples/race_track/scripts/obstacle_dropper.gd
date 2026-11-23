# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Node

const AHEAD := 50.0
const SPACING := 25.0
const LANE := 2.5
const FALL_HEIGHT := 12.0
const FALL_SECONDS := 0.6

@export var agent_path: NodePath

@onready var agent: RaceTrackAgent = get_node(agent_path)
var dropped: Array[Dictionary] = []
var _right_clicks: Array[Vector2] = []
var _removed: Array[StaticBody3D] = []


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var third := floori(3.0 * click.position.x / get_viewport().get_visible_rect().size.x)
		drop([LANE, 0.0, -LANE][clampi(third, 0, 2)])
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		_right_clicks.append(click.position)
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		clear()
	if key != null and key.pressed and not key.echo and key.keycode == KEY_DELETE and not dropped.is_empty():
		_free(dropped.pop_back())


func drop(side: float) -> void:
	var track := agent.track
	var length := track.curve.get_baked_length()
	var offset := fposmod(track.progress_of(agent.car.global_position) + AHEAD, length)
	var searched := 0.0
	while not _allowed(offset):
		offset = fposmod(offset + 1.0, length)
		searched += 1.0
		if searched > length:
			return
	var body := track.add_obstacle(offset, side)
	var landing := body.global_position
	body.global_position = landing + Vector3.UP * FALL_HEIGHT
	var marker := MeshInstance3D.new()
	var mark := BoxMesh.new()
	mark.size = Vector3(track.obstacle_size.x + 0.6, 0.02, track.obstacle_size.z + 0.6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.95, 0.2, 0.1, 0.6)
	mark.material = material
	marker.mesh = mark
	track.add_child(marker)
	marker.global_transform = Transform3D(body.global_basis, landing - Vector3.UP * (track.obstacle_size.y * 0.5 - 0.03))
	var fall := create_tween()
	fall.tween_property(body, "global_position", landing, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_callback(marker.queue_free)
	dropped.append({"body": body, "marker": marker, "offset": offset})


func clear() -> void:
	for item in dropped:
		_free(item)
	dropped.clear()
	for body in _removed:
		RaceTrackPath.set_solid(body, true)
	_removed.clear()


func _physics_process(_delta: float) -> void:
	for position in _right_clicks:
		_remove_at(position)
	_right_clicks.clear()


func _remove_at(position: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	var from := camera.project_ray_origin(position)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(position) * 1000.0, 0xFFFFFFFF, [agent.car.get_rid()])
	remove(camera.get_world_3d().direct_space_state.intersect_ray(query).get("collider") as StaticBody3D)


func remove(body: StaticBody3D) -> void:
	if body == null or not body.is_in_group("obstacle"):
		return
	for item in dropped:
		if item.body == body:
			_free(item)
			dropped.erase(item)
			return
	_removed.append(body)
	RaceTrackPath.set_solid(body, false)


func _allowed(offset: float) -> bool:
	var track := agent.track
	if not track.is_clear(offset):
		return false
	var length := track.curve.get_baked_length()
	for item in dropped:
		if absf(wrapf(item.offset - offset, -length * 0.5, length * 0.5)) < SPACING:
			return false
	return true


func _free(item: Dictionary) -> void:
	for node in [item.body, item.marker]:
		if is_instance_valid(node):
			node.queue_free()
