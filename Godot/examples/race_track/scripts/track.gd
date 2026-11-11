class_name RaceTrackPath
extends Path3D

const START_OFFSET_BACK := -4.0
const START_OFFSET_LEFT := 0.0


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

func _edge(offset: float, side: float) -> Vector3:
	var tangent := direction_at(offset)
	return curve.sample_baked(offset) + Vector3.UP.cross(tangent) * side * 5.5
