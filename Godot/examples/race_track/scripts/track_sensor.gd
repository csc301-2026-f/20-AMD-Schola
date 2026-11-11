# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackSensor
extends ScholaSensor

## Track-relative features belong to this example; velocity is a reusable sensor.
@export var body_path: NodePath
@export var location_scale: float = 5.0

func _init() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([6])
	box.low = PackedFloat32Array([-100000.0])
	box.high = PackedFloat32Array([100000.0])
	space = box

func _observe() -> Variant:
	var car := get_node(body_path) as Node3D
	var track := RaceTrackPath.find_in(get_tree())
	var offset := track.progress_of(car.global_position)
	var to_car_frame := car.global_basis.inverse()
	var location := _forward_right_up(to_car_frame * (track.center_at(offset) - car.global_position)) / location_scale
	var direction := _forward_right_up(to_car_frame * track.direction_at(offset))
	return PackedFloat32Array([location.x, location.y, location.z, direction.x, direction.y, direction.z])

func _forward_right_up(local: Vector3) -> Vector3:
	return Vector3(local.z, -local.x, local.y)

func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not get_node_or_null(body_path) is Node3D:
		errors.append("body_path must reference a Node3D.")
	if RaceTrackPath.find_in(get_tree()) == null:
		errors.append("The scene requires a RaceTrackPath.")
	if not is_finite(location_scale) or location_scale <= 0.0:
		errors.append("location_scale must be finite and positive.")
	return errors
