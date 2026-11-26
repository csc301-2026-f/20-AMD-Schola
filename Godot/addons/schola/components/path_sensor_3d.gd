# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaPathSensor3D
extends ScholaSensor

## Reports, in this order and expressed in the observed body frame: the path point
## offset, the path tangent, and normalized progress along the path. Each feature
## can be disabled, and has_x/has_y/has_z select vector components.
@export var body_path: NodePath:
	set(value):
		body_path = value
		update_configuration_warnings()
@export var path_path: NodePath:
	set(value):
		path_path = value
		update_configuration_warnings()
@export var location_scale: float = 1.0:
	set(value):
		location_scale = value
		update_configuration_warnings()
@export_enum("XYZ", "Forward Right Up (+Z)") var axes: int = 0
## Distance along the path, beyond the closest point, where the point and tangent
## are sampled. Closed curves wrap; open curves stop at their end.
@export var look_ahead: float = 0.0:
	set(value):
		look_ahead = value
		update_configuration_warnings()

@export_group("Features")
@export var include_location := true:
	set(value):
		include_location = value
		_refresh_space()
@export var include_direction := true:
	set(value):
		include_direction = value
		_refresh_space()
## Closest-point offset divided by the curve length, bounded in [0, 1].
@export var include_progress := false:
	set(value):
		include_progress = value
		_refresh_space()
## Include the first, second, and third component of each vector feature.
@export var has_x := true:
	set(value):
		has_x = value
		_refresh_space()
@export var has_y := true:
	set(value):
		has_y = value
		_refresh_space()
@export var has_z := true:
	set(value):
		has_z = value
		_refresh_space()
## Symmetric Box bound for the location and direction values.
@export var bound: float = 100000.0:
	set(value):
		bound = value
		_refresh_space()


func _init() -> void:
	_refresh_space()


func get_axis_mask() -> Array[bool]:
	return [has_x, has_y, has_z]


func get_value_count() -> int:
	var components := get_axis_mask().count(true)
	return components * (int(include_location) + int(include_direction)) + int(include_progress)


func _refresh_space() -> void:
	var box := ScholaBoxSpace.new()
	var count := get_value_count()
	box.shape = PackedInt32Array([count])
	if include_progress:
		var low := PackedFloat32Array()
		var high := PackedFloat32Array()
		for index in count - 1:
			low.append(-bound)
			high.append(bound)
		low.append(0.0)
		high.append(1.0)
		box.low = low
		box.high = high
	else:
		box.low = PackedFloat32Array([-bound])
		box.high = PackedFloat32Array([bound])
	space = box
	update_configuration_warnings()


func _validate_property(property: Dictionary) -> void:
	if property.name == "space":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _observe() -> Variant:
	if not _get_component_errors().is_empty():
		return null # The adapter reports invalid configuration/value.
	var car := get_node(body_path) as Node3D
	var path := get_node(path_path) as Path3D
	var curve := path.curve
	var offset := curve.get_closest_offset(path.to_local(car.global_position))
	var length := curve.get_baked_length()
	var sample_offset := _along(offset + look_ahead, length, curve.closed)
	var start := sample_offset if curve.closed else maxf(0.0, minf(sample_offset, length - 1.0))
	var end := _along(start + 1.0, length, curve.closed)
	var center := path.to_global(curve.sample_baked(sample_offset))
	var tangent := (path.to_global(curve.sample_baked(end)) - path.to_global(curve.sample_baked(start))).normalized()
	var to_car_frame := car.global_basis.inverse()
	var values := PackedFloat32Array()
	if include_location:
		_append_vector(values, _forward_right_up(to_car_frame * (center - car.global_position)) / location_scale)
	if include_direction:
		_append_vector(values, _forward_right_up(to_car_frame * tangent))
	if include_progress:
		values.append(clampf(offset / length, 0.0, 1.0))
	for index in values.size() - int(include_progress):
		values[index] = clampf(values[index], -bound, bound)
	return values


func _along(offset: float, length: float, closed: bool) -> float:
	return fposmod(offset, length) if closed else clampf(offset, 0.0, length)


func _append_vector(values: PackedFloat32Array, vector: Vector3) -> void:
	var mask := get_axis_mask()
	for axis in 3:
		if mask[axis]:
			values.append(vector[axis])


func _forward_right_up(local: Vector3) -> Vector3:
	return Vector3(local.z, -local.x, local.y) if axes == 1 else local


func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not get_node_or_null(body_path) is Node3D:
		errors.append("body_path must reference a Node3D.")
	var path := get_node_or_null(path_path) as Path3D
	if path == null or path.curve == null or path.curve.get_baked_length() <= 0.0:
		errors.append("path_path must reference a Path3D with a nonempty curve.")
	if not is_finite(location_scale) or location_scale <= 0.0:
		errors.append("location_scale must be finite and positive.")
	if not is_finite(look_ahead):
		errors.append("look_ahead must be finite.")
	if not is_finite(bound) or bound <= 0.0:
		errors.append("bound must be finite and positive.")
	if get_value_count() == 0:
		errors.append("Enable at least one path feature and vector component.")
	var box := space as ScholaBoxSpace
	if box == null or box.shape != PackedInt32Array([get_value_count()]):
		errors.append("Path space must match the enabled features and components.")
	return errors
