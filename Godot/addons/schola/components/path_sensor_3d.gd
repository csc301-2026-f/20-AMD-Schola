# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaPathSensor3D
extends ScholaSensor

## Closest path offset and tangent, expressed in the observed body frame.
@export var body_path: NodePath
@export var path_path: NodePath
@export var location_scale: float = 1.0
@export_enum("XYZ", "Forward Right Up (+Z)") var axes: int = 0

func _init() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([6])
	box.low = PackedFloat32Array([-100000.0])
	box.high = PackedFloat32Array([100000.0])
	space = box

func _observe() -> Variant:
	var car := get_node(body_path) as Node3D
	var path := get_node(path_path) as Path3D
	var offset := path.curve.get_closest_offset(path.to_local(car.global_position))
	var length := path.curve.get_baked_length()
	var start := maxf(0.0, minf(offset, length - 1.0))
	var center := path.to_global(path.curve.sample_baked(offset))
	var tangent := (path.to_global(path.curve.sample_baked(minf(start + 1.0, length))) - path.to_global(path.curve.sample_baked(start))).normalized()
	var to_car_frame := car.global_basis.inverse()
	var location := _forward_right_up(to_car_frame * (center - car.global_position)) / location_scale
	var direction := _forward_right_up(to_car_frame * tangent)
	return PackedFloat32Array([location.x, location.y, location.z, direction.x, direction.y, direction.z])

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
	return errors
