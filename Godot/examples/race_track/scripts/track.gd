# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackPath
extends Path3D

const START_OFFSET_BACK := -4.0
const START_OFFSET_LEFT := 0.0

@export var obstacles := PackedVector2Array()
@export var obstacle_size := Vector3(2.5, 1.0, 1.0)
@export var jumps := PackedFloat32Array()
@export var jump_size := Vector3(10.0, 1.4, 6.0)


static func find_in(tree: SceneTree) -> RaceTrackPath:
	return tree.get_first_node_in_group("race_track") as RaceTrackPath


func progress_of(global_point: Vector3) -> float:
	return curve.get_closest_offset(to_local(global_point))


func center_at(offset: float) -> Vector3:
	return to_global(curve.sample_baked(clampf(offset, 0.0, curve.get_baked_length())))


func direction_at(offset: float) -> Vector3:
	var start := clampf(offset, 0.0, curve.get_baked_length() - 1.0)
	return (center_at(start + 1.0) - center_at(start)).normalized()


func distance_from_center(global_point: Vector3) -> float:
	return global_point.distance_to(center_at(progress_of(global_point)))


func start_transform() -> Transform3D:
	var forward := direction_at(0.0)
	var left := Vector3.UP.cross(forward)
	var start := center_at(0.0) - forward * START_OFFSET_BACK + left * START_OFFSET_LEFT + Vector3.UP
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
		if ahead < 30.0 or ahead > length - 10.0:
			return false
	return true

## Sample both edges into solid walls; width stays in metres when course points shrink.
func _ready() -> void:
	var walls := StaticBody3D.new()
	walls.name = "TrackWalls"
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
	_add_obstacles()
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


func _add_obstacles() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.45, 0.1)
	for obstacle in obstacles:
		var forward := direction_at(obstacle.x)
		var body := StaticBody3D.new()
		body.add_to_group("obstacle")
		add_child(body)
		body.global_transform = Transform3D(Basis.looking_at(-forward, Vector3.UP), center_at(obstacle.x) + Vector3.UP.cross(forward).normalized() * obstacle.y + Vector3.UP * obstacle_size.y * 0.5)
		var shape := BoxShape3D.new()
		shape.size = obstacle_size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		var mesh := BoxMesh.new()
		mesh.size = obstacle_size
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material
		body.add_child(visual)

func _edge(offset: float, side: float) -> Vector3:
	var tangent := direction_at(offset)
	return curve.sample_baked(offset) + Vector3.UP.cross(tangent) * side * 5.5
