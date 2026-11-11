# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaRayCastSensor3D
extends ScholaSensor

## Reports [hit, normalized distance] for each RayCast3D in exported path-array order.
## Misses report [0, 0], matching Schola's ray sensor semantics.
@export var rays: Array[NodePath] = []:
	set(value):
		rays = value.duplicate()
		_refresh_space()


func _init() -> void:
	_refresh_space()


## Use assignment or add_ray() to update paths and their advertised space together.
## Raw in-place Array edits bypass GDScript setters and are reported as errors.
func add_ray(path: NodePath) -> void:
	var updated := rays.duplicate()
	updated.append(path)
	rays = updated


func _refresh_space() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([rays.size() * 2])
	box.low = PackedFloat32Array([0.0])
	box.high = PackedFloat32Array([1.0])
	space = box
	update_configuration_warnings()


func _observe() -> Variant:
	if not _get_component_errors().is_empty():
		return null
	var values := PackedFloat32Array()
	for path in rays:
		var ray := get_node_or_null(path) as RayCast3D
		if ray == null or ray.target_position.length() <= 0.0:
			return null # The adapter reports invalid configuration/value.
		ray.force_raycast_update()
		if ray.is_colliding():
			var distance := ray.global_position.distance_to(ray.get_collision_point())
			var length := ray.global_position.distance_to(ray.to_global(ray.target_position))
			values.append(1.0)
			values.append(clampf(distance / length, 0.0, 1.0))
		else:
			values.append(0.0)
			values.append(0.0)
	return values


func _get_component_errors() -> PackedStringArray:
	var warnings := PackedStringArray()
	var box := space as ScholaBoxSpace
	if box == null or box.shape != PackedInt32Array([rays.size() * 2]):
		warnings.append("Ray space must have two values per ray; reassign rays or use add_ray() to synchronize it.")
	if rays.is_empty():
		warnings.append("Assign at least one RayCast3D path.")
	for path in rays:
		var ray := get_node_or_null(path) as RayCast3D
		if ray == null:
			warnings.append("Ray path must reference a RayCast3D: " + str(path))
		elif ray.target_position.length() <= 0.0:
			warnings.append("Ray target_position must have nonzero length.")
	return warnings
