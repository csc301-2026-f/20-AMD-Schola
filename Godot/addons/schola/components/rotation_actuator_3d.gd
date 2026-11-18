# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaRotationActuator3D
extends ScholaActuator

## Local Euler increments in degrees, ordered pitch(X), yaw(Y), roll(Z).
signal rotation_input(delta_degrees: Vector3)

@export var target_path: NodePath:
	set(value):
		target_path = value
		update_configuration_warnings()
@export var enabled_axes: Vector3i = Vector3i.ONE:
	set(value):
		enabled_axes = value
		_refresh_space()
@export var lower_degrees: Vector3 = Vector3(-180, -180, -180):
	set(value):
		lower_degrees = value
		_refresh_space()
@export var upper_degrees: Vector3 = Vector3(180, 180, 180):
	set(value):
		upper_degrees = value
		_refresh_space()
@export var normalized_input: bool = false:
	set(value):
		normalized_input = value
		_refresh_space()

func _init() -> void:
	_refresh_space()

func _expected_space() -> ScholaBoxSpace:
	var low := PackedFloat32Array()
	var high := PackedFloat32Array()
	for axis in 3:
		if enabled_axes[axis] != 0:
			low.append(0.0 if normalized_input else lower_degrees[axis])
			high.append(1.0 if normalized_input else upper_degrees[axis])
	return ScholaComponentSpace.box(PackedInt32Array([low.size()]), low, high)

func _refresh_space() -> void:
	space = _expected_space()
	update_configuration_warnings()

func _act(action: Variant) -> void:
	var delta := Vector3.ZERO
	var index := 0
	for axis in 3:
		if enabled_axes[axis] != 0:
			delta[axis] = lerpf(lower_degrees[axis], upper_degrees[axis], action[index]) if normalized_input else action[index]
			index += 1
	var target := get_node_or_null(target_path) as Node3D
	rotation_input.emit(delta)
	if is_instance_valid(target):
		# Compose rotations independently from scale to avoid shearing scaled targets.
		target.quaternion = (target.quaternion * Quaternion.from_euler(delta * (PI / 180.0))).normalized()

func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		errors.append("target_path must reference a Node3D.")
	elif not ScholaComponentSpace.is_usable_basis(target.basis):
		errors.append("Rotation requires a finite target basis that can be normalized.")
	if not ScholaComponentSpace.matches(space, _expected_space()):
		errors.append("Rotation space must match enabled_axes, bounds and normalized_input.")
	if enabled_axes == Vector3i.ZERO:
		errors.append("Enable at least one rotation axis.")
	for axis in 3:
		if enabled_axes[axis] != 0 and (not is_finite(lower_degrees[axis]) or not is_finite(upper_degrees[axis]) or lower_degrees[axis] > upper_degrees[axis]):
			errors.append("Enabled rotation bounds must be finite and ordered.")
	return errors
