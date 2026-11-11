# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaVelocitySensor3D
extends ScholaSensor

## Reads linear velocity from either Godot physics body type, in m/s / velocity_scale.
@export var body_path: NodePath
@export var local_frame := true
## XYZ is Godot-native. FORWARD_RIGHT_UP matches vehicles facing local +Z.
@export_enum("XYZ", "Forward Right Up (+Z)") var axes: int = 0
@export var velocity_scale: float = 1.0

func _init() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([3])
	space = box

func _observe() -> Variant:
	var body := get_node_or_null(body_path)
	var velocity: Vector3 = body.linear_velocity if body is RigidBody3D else body.velocity
	if local_frame:
		velocity = body.global_basis.orthonormalized().inverse() * velocity
	if axes == 1:
		velocity = Vector3(velocity.z, -velocity.x, velocity.y)
	velocity /= velocity_scale
	return PackedFloat32Array([velocity.x, velocity.y, velocity.z])

func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var body := get_node_or_null(body_path)
	if not (body is RigidBody3D or body is CharacterBody3D):
		errors.append("body_path must reference a RigidBody3D or CharacterBody3D.")
	if not is_finite(velocity_scale) or velocity_scale <= 0.0:
		errors.append("velocity_scale must be finite and positive.")
	if axes < 0 or axes > 1:
		errors.append("axes must be XYZ or Forward Right Up.")
	return errors
