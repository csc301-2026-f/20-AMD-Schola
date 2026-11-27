# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackPath
extends Path3D

const START_OFFSET_AHEAD := 4.0
const LANE := 2.5
const LANES: Array[float] = [LANE, 0.0, -LANE]
const ROAD_HALF_WIDTH := 5.5
const START_CLEAR_AHEAD := 30.0
const START_CLEAR_BEHIND := 10.0
const OBSTACLE_SPACING := 25.0
const GATE_SPACING := Vector2(20.0, 26.0)
const CLEAR_AFTER_START := 45.0
const CLEAR_BEFORE_START := 15.0
const CLEAR_BEFORE_JUMP := 30.0
const CLEAR_AFTER_JUMP := 45.0

@export var obstacles := PackedVector2Array()
@export var obstacle_size := Vector3(2.5, 1.0, 1.0)
@export var jumps := PackedFloat32Array()
@export var jump_size := Vector3(10.0, 1.4, 6.0)

var map_obstacles := PackedVector2Array()
var _obstacle_bodies: Array[StaticBody3D] = []


static func find_for(node: Node) -> RaceTrackPath:
	var tracks := node.get_tree().get_nodes_in_group("race_track")
	var ancestor := node.get_parent()
	while ancestor != null:
		for track in tracks:
			if ancestor.is_ancestor_of(track):
				return track
		ancestor = ancestor.get_parent()
	return null


func progress_of(global_point: Vector3) -> float:
	return curve.get_closest_offset(to_local(global_point))


func center_at(offset: float) -> Vector3:
	return to_global(curve.sample_baked(clampf(offset, 0.0, curve.get_baked_length())))


func direction_at(offset: float) -> Vector3:
	var start := clampf(offset, 0.0, curve.get_baked_length() - 1.0)
	return (center_at(start + 1.0) - center_at(start)).normalized()


func offset_between(from_offset: float, to_offset: float) -> float:
	var length := curve.get_baked_length()
	return wrapf(to_offset - from_offset, -length * 0.5, length * 0.5)


func distance_from_center(global_point: Vector3) -> float:
	return global_point.distance_to(center_at(progress_of(global_point)))


func start_transform() -> Transform3D:
	var forward := direction_at(0.0)
	var start := center_at(0.0) + forward * START_OFFSET_AHEAD + Vector3.UP
	return Transform3D(Basis.looking_at(-forward, Vector3.UP), start)


func transform_at(offset: float) -> Transform3D:
	var forward := direction_at(offset)
	return Transform3D(Basis.looking_at(-forward, Vector3.UP), center_at(offset) + Vector3.UP)


func is_clear(offset: float) -> bool:
	var length := curve.get_baked_length()
	var blocked := Array(jumps)
	for obstacle in obstacles:
		blocked.append(obstacle.x)
	for start in blocked:
		var ahead := fposmod(start - offset, length)
		if ahead < START_CLEAR_AHEAD or ahead > length - START_CLEAR_BEHIND:
			return false
	return true

## Sample both edges into solid walls; width stays in metres when course points shrink.
func _ready() -> void:
	var walls := StaticBody3D.new()
	walls.name = "TrackWalls"
	walls.add_to_group("wall")
	add_child(walls)
	var length := curve.get_baked_length()
	var segments := ceili(length / 1.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.58, 0.62)
	for side in [-1.0, 1.0]:
		for index in segments:
			var a := _edge(length * index / segments, side)
			var b := _edge(length * (index + 1) / segments, side)
			var size := Vector3(0.5, 1.2, a.distance_to(b) + 0.15)
			var pose := Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5 + Vector3.UP * 0.6)
			var shape := BoxShape3D.new()
			shape.size = size
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.transform = pose
			walls.add_child(collision)
			var mesh := BoxMesh.new()
			mesh.size = size
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.material_override = material
			visual.transform = pose
			walls.add_child(visual)
	map_obstacles = obstacles
	set_obstacles(obstacles)
	_add_jumps()


func _add_jumps() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.8, 0.1)
	var ramp := PrismMesh.new()
	ramp.left_to_right = 1.0
	ramp.size = Vector3(jump_size.z, jump_size.y, jump_size.x)
	ramp.material = material
	var shape := ramp.create_convex_shape()
	var turn := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.UP * jump_size.y * 0.5)
	for offset in jumps:
		var forward := direction_at(offset)
		var body := StaticBody3D.new()
		add_child(body)
		body.global_transform = Transform3D(Basis.looking_at(-forward, Vector3.UP), center_at(offset))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = turn
		body.add_child(collision)
		var visual := MeshInstance3D.new()
		visual.mesh = ramp
		visual.transform = turn
		body.add_child(visual)


func set_obstacles(layout: PackedVector2Array) -> void:
	obstacles = layout
	while _obstacle_bodies.size() < layout.size():
		_obstacle_bodies.append(_new_obstacle())
	for index in _obstacle_bodies.size():
		var body := _obstacle_bodies[index]
		set_solid(body, index < layout.size())
		if body.visible:
			_move_obstacle(body, layout[index].x, layout[index].y)


static func set_solid(body: CollisionObject3D, solid: bool) -> void:
	body.visible = solid
	body.collision_layer = 1 if solid else 0
	body.collision_mask = 1 if solid else 0


func random_obstacle_layout(rng: RandomNumberGenerator) -> PackedVector2Array:
	var layout := PackedVector2Array()
	var density := rng.randf()
	var singles := rng.randi_range(0, 2)
	var clusters := 0
	if density >= 0.9:
		singles = rng.randi_range(8, 12)
		clusters = rng.randi_range(1, 2)
	elif density >= 0.65:
		singles = rng.randi_range(6, 10)
		clusters = rng.randi_range(0, 1)
	elif density >= 0.2:
		singles = rng.randi_range(3, 8)
	var length := curve.get_baked_length()
	for cluster in clusters:
		for attempt in 20:
			var candidate := PackedVector2Array()
			var offset := rng.randf() * length
			var open := LANE if rng.randf() < 0.5 else -LANE
			for gate in rng.randi_range(2, 4):
				for side in LANES:
					if side != open:
						candidate.append(Vector2(fposmod(offset, length), side))
				open = -open
				offset += rng.randf_range(GATE_SPACING.x, GATE_SPACING.y)
			if _fits(candidate, layout):
				layout.append_array(candidate)
				break
	for single in singles:
		for attempt in 20:
			var candidate := PackedVector2Array([Vector2(rng.randf() * length, LANES[rng.randi_range(0, 2)])])
			if _fits(candidate, layout):
				layout.append_array(candidate)
				break
	return layout


func _fits(candidate: PackedVector2Array, layout: PackedVector2Array) -> bool:
	var length := curve.get_baked_length()
	for obstacle in candidate:
		if obstacle.x < CLEAR_AFTER_START or obstacle.x > length - CLEAR_BEFORE_START:
			return false
		for jump in jumps:
			var ahead := fposmod(jump - obstacle.x, length)
			if ahead < CLEAR_BEFORE_JUMP or ahead > length - CLEAR_AFTER_JUMP:
				return false
		for other in layout:
			if absf(offset_between(obstacle.x, other.x)) < OBSTACLE_SPACING:
				return false
	return true


func _move_obstacle(body: StaticBody3D, offset: float, side: float) -> void:
	var forward := direction_at(offset)
	body.global_transform = Transform3D(Basis.looking_at(-forward, Vector3.UP), center_at(offset) + Vector3.UP.cross(forward).normalized() * side + Vector3.UP * obstacle_size.y * 0.5)
	body.set_meta("track_offset", offset)
	body.set_meta("track_side", side)


func add_obstacle(offset: float, side: float) -> StaticBody3D:
	var body := _new_obstacle()
	_move_obstacle(body, offset, side)
	return body


func _new_obstacle() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("obstacle")
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = obstacle_size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := BoxMesh.new()
	mesh.size = obstacle_size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.45, 0.1)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	return body

func _edge(offset: float, side: float) -> Vector3:
	var tangent := direction_at(offset)
	return curve.sample_baked(offset) + Vector3.UP.cross(tangent) * side * ROAD_HALF_WIDTH
