# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaMovementActuator3D
extends ScholaActuator

## Sets the velocity of a CharacterBody3D or RigidBody3D along each enabled axis.
## One continuous action value per enabled axis, in X/Y/Z order, bounded by
## [member minimum_speed] and [member maximum_speed]. Disabled axes keep the body's
## current velocity, so gravity or jumping can stay with the body's own physics.
## A CharacterBody3D's physics loop owns move_and_slide() and collision response.
@export var body_path: NodePath:
	set(value):
		body_path = value
		update_configuration_warnings()
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
## Lowest action value per axis. Set negative to allow backward movement.
@export var minimum_speed: float = -1.0:
	set(value):
		minimum_speed = value
		_refresh_space()
@export var maximum_speed: float = 1.0:
	set(value):
		maximum_speed = value
		_refresh_space()
## Multiplies each action value before it becomes velocity, in m/s per action unit.
@export var speed_scale: float = 1.0:
	set(value):
		speed_scale = value
		update_configuration_warnings()
## Interpret axes in the body's rotated frame. Disable for world X/Y/Z.
@export var local_frame := true


func _init() -> void:
	_refresh_space()


func get_axis_mask() -> Array[bool]:
	return [has_x, has_y, has_z]


func _refresh_space() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([get_axis_mask().count(true)])
	box.low = PackedFloat32Array([minimum_speed])
	box.high = PackedFloat32Array([maximum_speed])
	space = box
	update_configuration_warnings()


func _validate_property(property: Dictionary) -> void:
	if property.name == "space":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _act(action: Variant) -> void:
	var node := get_node_or_null(body_path)
	var character := node as CharacterBody3D
	var rigid := node as RigidBody3D
	if character == null and rigid == null:
		push_error("ScholaMovementActuator3D requires a CharacterBody3D or RigidBody3D body_path.")
		return
	var body: Node3D = character if character != null else rigid
	var frame := body.global_basis.orthonormalized() if local_frame else Basis.IDENTITY
	var velocity := frame.inverse() * (character.velocity if character != null else rigid.linear_velocity)
	var index := 0
	var mask := get_axis_mask()
	for axis in 3:
		if mask[axis]:
			velocity[axis] = clampf(action[index], minimum_speed, maximum_speed) * speed_scale
			index += 1
	if character != null:
		character.velocity = frame * velocity
	else:
		rigid.linear_velocity = frame * velocity


func _get_component_errors() -> PackedStringArray:
	var warnings := PackedStringArray()
	var body := get_node_or_null(body_path)
	if not (body is CharacterBody3D or body is RigidBody3D):
		warnings.append("body_path must reference a CharacterBody3D or RigidBody3D.")
	if not (has_x or has_y or has_z):
		warnings.append("Enable at least one movement axis.")
	if not is_finite(minimum_speed) or not is_finite(maximum_speed) or minimum_speed >= maximum_speed:
		warnings.append("minimum_speed and maximum_speed must be finite, with minimum below maximum.")
	if not is_finite(speed_scale):
		warnings.append("speed_scale must be finite.")
	var box := space as ScholaBoxSpace
	if box == null or box.shape != PackedInt32Array([get_axis_mask().count(true)]):
		warnings.append("Movement space must have one value per enabled axis.")
	return warnings
