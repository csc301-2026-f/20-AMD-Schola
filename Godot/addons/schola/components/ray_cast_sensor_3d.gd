# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaRayCastSensor3D
extends ScholaSensor

## Reports one slice per ray: [tracked group flags..., hit, normalized distance].
## Misses report all zeros, matching Schola's ray sensor semantics. Rays come from
## the RayCast3D nodes in [member rays] first, then from the [member num_rays]
## rays this sensor fans out itself from [member origin_path].

## Existing RayCast3D nodes, observed in array order. Their masks and exclusions apply.
@export var rays: Array[NodePath] = []:
	set(value):
		rays = value.duplicate()
		_refresh_space()

@export_group("Generated Rays")
## Number of rays generated across [member ray_degrees]. Zero disables generation.
@export_range(0, 256, 1, "or_greater") var num_rays: int = 0:
	set(value):
		num_rays = value
		_refresh_space()
## Node3D whose position and orientation cast the generated rays. Blank uses the
## nearest Node3D ancestor, such as the body that owns the agent.
@export var origin_path: NodePath:
	set(value):
		origin_path = value
		update_configuration_warnings()
## Angle between the first and last ray, fanned left to right around the origin's -Z.
## 360 places rays evenly around a full circle without overlapping the first one.
@export_range(0.0, 360.0, 0.1) var ray_degrees: float = 90.0:
	set(value):
		ray_degrees = value
		update_configuration_warnings()
@export var ray_length: float = 10.0:
	set(value):
		ray_length = value
		update_configuration_warnings()
## Offset added to every generated ray end point, in the origin's local frame.
@export var ray_end_offset := Vector3.ZERO
@export_flags_3d_physics var collision_mask: int = 1
@export var collide_with_bodies := true
@export var collide_with_areas := false
## Ignore the first CollisionObject3D at or above the origin, such as the agent's own body.
@export var exclude_origin_body := true

@export_group("Tracked Groups")
## Node groups checked on each hit collider. Each adds one 0/1 flag per ray,
## before the hit and distance values, like Unreal Schola's tracked tags.
@export var tracked_groups: Array[StringName] = []:
	set(value):
		tracked_groups = value.duplicate()
		_refresh_space()


func _init() -> void:
	_refresh_space()


## Use assignment or add_ray() to update paths and their advertised space together.
## Raw in-place Array edits bypass GDScript setters and are reported as errors.
func add_ray(path: NodePath) -> void:
	var updated := rays.duplicate()
	updated.append(path)
	rays = updated


func get_ray_count() -> int:
	return rays.size() + maxi(num_rays, 0)


func get_values_per_ray() -> int:
	return tracked_groups.size() + 2


## Local end points of the generated rays, before ray_end_offset.
func get_generated_ray_targets() -> PackedVector3Array:
	var targets := PackedVector3Array()
	if num_rays <= 0:
		return targets
	var full_circle := ray_degrees >= 360.0 or num_rays == 1
	var step := ray_degrees / (num_rays if full_circle else num_rays - 1)
	for index in num_rays:
		# Positive angles about +Y turn -Z toward -X, so the fan starts on the left.
		var angle := deg_to_rad(ray_degrees * 0.5 - step * index)
		targets.append(Basis(Vector3.UP, angle) * Vector3(0.0, 0.0, -ray_length))
	return targets


func _refresh_space() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([get_ray_count() * get_values_per_ray()])
	box.low = PackedFloat32Array([0.0])
	box.high = PackedFloat32Array([1.0])
	space = box
	update_configuration_warnings()


func _validate_property(property: Dictionary) -> void:
	if property.name == "space":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _observe() -> Variant:
	if not _get_component_errors().is_empty():
		return null # The adapter reports invalid configuration/value.
	var values := PackedFloat32Array()
	for path in rays:
		var ray := get_node(path) as RayCast3D
		ray.force_raycast_update()
		if ray.is_colliding():
			var distance := ray.global_position.distance_to(ray.get_collision_point())
			var length := ray.global_position.distance_to(ray.to_global(ray.target_position))
			_append_hit(values, ray.get_collider(), distance / length)
		else:
			_append_miss(values)
	if num_rays > 0:
		_cast_generated(values)
	return values


func _cast_generated(values: PackedFloat32Array) -> void:
	var origin := _origin()
	var state := origin.get_world_3d().direct_space_state
	var start := origin.global_position
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.collide_with_bodies = collide_with_bodies
	query.collide_with_areas = collide_with_areas
	var excluded := _excluded_body(origin)
	if excluded != null:
		var exclude: Array[RID] = [excluded.get_rid()]
		query.exclude = exclude
	for target in get_generated_ray_targets():
		var end := origin.global_transform * (target + ray_end_offset)
		query.from = start
		query.to = end
		var hit := state.intersect_ray(query)
		if hit.is_empty():
			_append_miss(values)
		else:
			_append_hit(values, hit.collider, start.distance_to(hit.position) / start.distance_to(end))


func _append_hit(values: PackedFloat32Array, collider: Object, fraction: float) -> void:
	var node := collider as Node
	for group in tracked_groups:
		values.append(1.0 if node != null and node.is_in_group(group) else 0.0)
	values.append(1.0)
	values.append(clampf(fraction, 0.0, 1.0))


func _append_miss(values: PackedFloat32Array) -> void:
	for index in get_values_per_ray():
		values.append(0.0)


func _origin() -> Node3D:
	if not origin_path.is_empty():
		return get_node_or_null(origin_path) as Node3D
	var parent := get_parent()
	while parent != null and not parent is Node3D:
		parent = parent.get_parent()
	return parent as Node3D


func _excluded_body(origin: Node3D) -> CollisionObject3D:
	if not exclude_origin_body:
		return null
	var node: Node = origin
	while node != null and not node is CollisionObject3D:
		node = node.get_parent()
	return node as CollisionObject3D


func _get_component_errors() -> PackedStringArray:
	var warnings := PackedStringArray()
	var box := space as ScholaBoxSpace
	if box == null or box.shape != PackedInt32Array([get_ray_count() * get_values_per_ray()]):
		warnings.append("Ray space must have one slice per ray; reassign rays/tracked_groups or use add_ray() to synchronize it.")
	if get_ray_count() == 0:
		warnings.append("Assign at least one RayCast3D path or set num_rays.")
	for path in rays:
		var ray := get_node_or_null(path) as RayCast3D
		if ray == null:
			warnings.append("Ray path must reference a RayCast3D: " + str(path))
		elif ray.target_position.length() <= 0.0:
			warnings.append("Ray target_position must have nonzero length.")
	if num_rays < 0:
		warnings.append("num_rays must not be negative.")
	if num_rays > 0:
		var origin := _origin()
		if origin == null:
			warnings.append("Generated rays need origin_path, or a Node3D ancestor, to cast from.")
		elif not origin.is_inside_tree():
			warnings.append("The generated-ray origin must be inside the scene tree.")
		if not is_finite(ray_length) or ray_length <= 0.0:
			warnings.append("ray_length must be finite and positive.")
		if not is_finite(ray_degrees) or ray_degrees < 0.0 or ray_degrees > 360.0:
			warnings.append("ray_degrees must be between 0 and 360.")
		for target in get_generated_ray_targets():
			if (target + ray_end_offset).is_zero_approx():
				warnings.append("ray_end_offset must not cancel a generated ray.")
				break
	for group in tracked_groups:
		if String(group).is_empty():
			warnings.append("Tracked group names must not be empty.")
			break
	return warnings
