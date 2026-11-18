# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaRayCastSensor3D
extends ScholaSensor

## Per ray: tracked group flags, hit flag, normalized distance. Misses are zero.
@export var rays: Array[NodePath] = []:
	set(value):
		rays = value.duplicate()
		_refresh_space()
@export var tracked_tags: PackedStringArray = PackedStringArray():
	set(value):
		tracked_tags = value.duplicate()
		_refresh_space()
@export var use_generated_rays: bool = false:
	set(value):
		use_generated_rays = value
		_refresh_space()
@export var origin_path: NodePath:
	set(value):
		origin_path = value
		update_configuration_warnings()
@export_range(1, 4096) var num_rays: int = 8:
	set(value):
		num_rays = value
		_refresh_space()
@export_range(0, 360) var ray_degrees: float = 90.0:
	set(value):
		ray_degrees = value
		update_configuration_warnings()
@export var ray_length: float = 10.0:
	set(value):
		ray_length = value
		update_configuration_warnings()
@export var end_offset: Vector3 = Vector3.ZERO:
	set(value):
		end_offset = value
		update_configuration_warnings()
@export_flags_3d_physics var collision_mask: int = 1
@export var collide_with_areas: bool = false
@export var exclude_paths: Array[NodePath] = []:
	set(value):
		exclude_paths = value
		update_configuration_warnings()
@export var draw_debug: bool = false:
	set(value):
		draw_debug = value
		if not value and is_instance_valid(_debug_instance):
			_debug_instance.visible = false
@export var debug_hit_color: Color = Color.GREEN
@export var debug_miss_color: Color = Color.RED
var _debug_instance: MeshInstance3D

func _init() -> void:
	_refresh_space()

func add_ray(path: NodePath) -> void:
	var updated := rays.duplicate()
	updated.append(path)
	rays = updated

func _ray_count() -> int:
	return num_rays if use_generated_rays else rays.size()

func _expected_space() -> ScholaBoxSpace:
	if _ray_count() < 1 or _ray_count() > 4096 or tracked_tags.size() > 256:
		return ScholaComponentSpace.box(PackedInt32Array([0]), PackedFloat32Array([0]), PackedFloat32Array([1]))
	return ScholaComponentSpace.box(PackedInt32Array([_ray_count() * (tracked_tags.size() + 2)]), PackedFloat32Array([0]), PackedFloat32Array([1]))

func _refresh_space() -> void:
	space = _expected_space()
	update_configuration_warnings()

## Origin-local endpoints; a full circle excludes the overlapping final ray.
func get_generated_endpoints() -> PackedVector3Array:
	var endpoints := PackedVector3Array()
	if num_rays < 1 or num_rays > 4096:
		return endpoints
	for index in num_rays:
		var angle := 0.0
		if num_rays > 1:
			angle = ray_degrees * 0.5 - ray_degrees * index / (num_rays if is_equal_approx(ray_degrees, 360.0) else num_rays - 1)
		endpoints.append(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle)) * ray_length)
	return endpoints

func _observe() -> Variant:
	if not _get_component_errors().is_empty():
		return null
	var values := PackedFloat32Array()
	var segments: Array = []
	if use_generated_rays:
		var origin := get_node(origin_path) as Node3D
		var exclusions: Array[RID] = []
		for path in exclude_paths:
			exclusions.append((get_node(path) as CollisionObject3D).get_rid())
		if origin is CollisionObject3D and not exclusions.has(origin.get_rid()):
			exclusions.append(origin.get_rid())
		for endpoint in get_generated_endpoints():
			var start := origin.global_position
			var end := (origin.to_global(endpoint) + end_offset)
			var query := PhysicsRayQueryParameters3D.create(start, end, collision_mask, exclusions)
			query.collide_with_areas = collide_with_areas
			var hit := origin.get_world_3d().direct_space_state.intersect_ray(query)
			_append_ray(values, segments, start, end, hit.get("collider"), hit.get("position", end))
	else:
		for path in rays:
			var ray := get_node(path) as RayCast3D
			ray.force_raycast_update()
			var end := ray.to_global(ray.target_position)
			_append_ray(values, segments, ray.global_position, end, ray.get_collider() if ray.is_colliding() else null, ray.get_collision_point() if ray.is_colliding() else end)
	_update_debug(segments)
	return values

func _append_ray(values: PackedFloat32Array, segments: Array, start: Vector3, end: Vector3, collider: Object, point: Vector3) -> void:
	for tag in tracked_tags:
		values.append(float(collider is Node and collider.is_in_group(tag)))
	values.append(float(collider != null))
	values.append(clampf(start.distance_to(point) / start.distance_to(end), 0, 1) if collider != null else 0.0)
	segments.append([start, point, collider != null])

func _update_debug(segments: Array) -> void:
	if not draw_debug:
		if is_instance_valid(_debug_instance):
			_debug_instance.visible = false
		return
	if not is_instance_valid(_debug_instance):
		_debug_instance = MeshInstance3D.new()
		_debug_instance.top_level = true
		add_child(_debug_instance, false, Node.INTERNAL_MODE_BACK)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		_debug_instance.material_override = material
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment in segments:
		mesh.surface_set_color(debug_hit_color if segment[2] else debug_miss_color)
		mesh.surface_add_vertex(segment[0])
		mesh.surface_add_vertex(segment[1])
	mesh.surface_end()
	_debug_instance.mesh = mesh
	_debug_instance.visible = true

func _process(_delta: float) -> void:
	if not draw_debug and is_instance_valid(_debug_instance):
		_debug_instance.visible = false
	if Engine.is_editor_hint() and draw_debug and _get_component_errors().is_empty():
		var segments: Array = []
		if use_generated_rays:
			var origin := get_node(origin_path) as Node3D
			for endpoint in get_generated_endpoints():
				segments.append([origin.global_position, (origin.to_global(endpoint) + end_offset), false])
		else:
			for path in rays:
				var ray := get_node(path) as RayCast3D
				segments.append([ray.global_position, ray.to_global(ray.target_position), false])
		_update_debug(segments)

func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ScholaComponentSpace.matches(space, _expected_space()):
		errors.append("Ray space must match the ray and tag counts; reassign rays or use add_ray() to synchronize it.")
	if _ray_count() < 1 or _ray_count() > 4096 or tracked_tags.size() > 256:
		errors.append("Use 1..4096 rays and at most 256 tracked tags.")
	if use_generated_rays:
		var origin := get_node_or_null(origin_path) as Node3D
		if origin == null:
			errors.append("origin_path must reference a Node3D.")
		if not is_finite(ray_degrees) or ray_degrees < 0 or ray_degrees > 360 or not is_finite(ray_length) or ray_length <= 0 or not end_offset.is_finite():
			errors.append("Generated rays require a finite positive length, finite offset and angle in [0,360].")
		else:
			for endpoint in get_generated_endpoints():
				if not _valid_segment(Vector3.ZERO, endpoint) or (origin != null and origin.is_inside_tree() and not _valid_segment(origin.global_position, origin.to_global(endpoint) + end_offset)):
					errors.append("Every generated ray must have finite endpoints and a nonzero world length.")
					break
		for path in exclude_paths:
			if not get_node_or_null(path) is CollisionObject3D:
				errors.append("exclude_paths must reference CollisionObject3D nodes.")
	else:
		for path in rays:
			var ray := get_node_or_null(path) as RayCast3D
			if ray == null:
				errors.append("Ray path must reference a RayCast3D: " + str(path))
			elif not _valid_segment(Vector3.ZERO, ray.target_position) or (ray.is_inside_tree() and not _valid_segment(ray.global_position, ray.to_global(ray.target_position))):
				errors.append("Ray target_position must have finite nonzero world length.")
	return errors

static func _valid_segment(start: Vector3, end: Vector3) -> bool:
	if not start.is_finite() or not end.is_finite():
		return false
	var length := start.distance_to(end)
	return is_finite(length) and length > 0.0
