class_name RaceTrackPath
extends Path3D

const START_OFFSET_BACK := 0.7
const START_OFFSET_LEFT := 8.2


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
