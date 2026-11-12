# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaVelocitySensor3D
extends ScholaSensor

## Reads linear velocity from either Godot physics body type, in m/s / velocity_scale.
## Reports one value per enabled component, in the order of the selected axes.
@export var body_path: NodePath:
	set(value):
		body_path = value
		update_configuration_warnings()
@export var local_frame := true
## XYZ is Godot-native. FORWARD_RIGHT_UP matches vehicles facing local +Z.
@export_enum("XYZ", "Forward Right Up (+Z)") var axes: int = 0:
	set(value):
		axes = value
		update_configuration_warnings()
@export var velocity_scale: float = 1.0:
	set(value):
		velocity_scale = value
		update_configuration_warnings()
## Include the first, second, and third component of the selected axes.
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
## Symmetric Box bound for the scaled values; observations are clamped to it.
## Zero leaves the Box unbounded so high speeds are not silently clipped.
@export var bound: float = 0.0:
	set(value):
		bound = value
		_refresh_space()


func _init() -> void:
	_refresh_space()


func get_axis_mask() -> Array[bool]:
	return [has_x, has_y, has_z]


func _refresh_space() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([get_axis_mask().count(true)])
	if bound > 0.0:
		box.low = PackedFloat32Array([-bound])
		box.high = PackedFloat32Array([bound])
	space = box
	update_configuration_warnings()


func _validate_property(property: Dictionary) -> void:
	if property.name == "space":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _observe() -> Variant:
	var node := get_node_or_null(body_path)
	var character := node as CharacterBody3D
	var rigid := node as RigidBody3D
	if character == null and rigid == null:
		return null # The adapter reports invalid configuration/value.
	var body: Node3D = character if character != null else rigid
	var velocity: Vector3 = rigid.linear_velocity if rigid != null else character.velocity
	if local_frame:
		velocity = body.global_basis.orthonormalized().inverse() * velocity
	if axes == 1:
		velocity = Vector3(velocity.z, -velocity.x, velocity.y)
	velocity /= velocity_scale
	var values := PackedFloat32Array()
	var mask := get_axis_mask()
	for axis in 3:
		if mask[axis]:
			values.append(clampf(velocity[axis], -bound, bound) if bound > 0.0 else velocity[axis])
	return values


func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var body := get_node_or_null(body_path)
	if not (body is RigidBody3D or body is CharacterBody3D):
		errors.append("body_path must reference a RigidBody3D or CharacterBody3D.")
	if not is_finite(velocity_scale) or velocity_scale <= 0.0:
		errors.append("velocity_scale must be finite and positive.")
	if axes < 0 or axes > 1:
		errors.append("axes must be XYZ or Forward Right Up.")
	if not (has_x or has_y or has_z):
		errors.append("Enable at least one velocity component.")
	if not is_finite(bound) or bound < 0.0:
		errors.append("bound must be finite and nonnegative.")
	var box := space as ScholaBoxSpace
	if box == null or box.shape != PackedInt32Array([get_axis_mask().count(true)]):
		errors.append("Velocity space must have one value per enabled component.")
	return errors
