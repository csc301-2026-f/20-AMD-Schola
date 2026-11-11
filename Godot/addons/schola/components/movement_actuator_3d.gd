# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaMovementActuator3D
extends ScholaActuator

## Applies local X/Y/Z velocity to a CharacterBody3D. The body's physics
## loop owns move_and_slide(), gravity, and collision response.
@export var body_path: NodePath:
	set(value):
		body_path = value
		update_configuration_warnings()
@export var maximum_speed: float = 1.0:
	set(value):
		maximum_speed = value
		_refresh_space()


func _init() -> void:
	_refresh_space()


func _refresh_space() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([3])
	box.low = PackedFloat32Array([-maximum_speed])
	box.high = PackedFloat32Array([maximum_speed])
	space = box
	update_configuration_warnings()


func _act(action: Variant) -> void:
	var body := get_node_or_null(body_path) as CharacterBody3D
	if body == null:
		push_error("ScholaMovementActuator3D requires a CharacterBody3D body_path.")
		return
	body.velocity = body.global_basis.orthonormalized() * Vector3(action[0], action[1], action[2])


func _get_component_errors() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_node_or_null(body_path) is CharacterBody3D:
		warnings.append("body_path must reference a CharacterBody3D.")
	if not is_finite(maximum_speed) or maximum_speed <= 0.0:
		warnings.append("maximum_speed must be finite and positive.")
	return warnings
