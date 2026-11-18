# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaMovementActuator3D
extends ScholaActuator

## Velocity in local X/Y/Z order, omitting disabled axes. Physics movement stays
## with the body's loop. Force bypasses this component's movement_enabled gate.
signal movement_input(local_velocity: Vector3)

@export var body_path: NodePath:
	set(value):
		body_path = value
		update_configuration_warnings()
@export var enabled_axes: Vector3i = Vector3i.ONE:
	set(value):
		enabled_axes = value
		_refresh_space()
@export var maximum_speed: float = 1.0:
	set(value):
		maximum_speed = value
		_refresh_space()
@export var symmetric_bounds: bool = true:
	set(value):
		symmetric_bounds = value
		_refresh_space()
@export var minimum_speed: float = -1.0:
	set(value):
		minimum_speed = value
		_refresh_space()
@export var input_scale: float = 1.0:
	set(value):
		input_scale = value
		update_configuration_warnings()
@export var movement_enabled: bool = true
@export var force: bool = false

func _init() -> void:
	_refresh_space()

func _expected_space() -> ScholaBoxSpace:
	return ScholaComponentSpace.box(PackedInt32Array([_axis_count()]),
		PackedFloat32Array([-maximum_speed if symmetric_bounds else minimum_speed]), PackedFloat32Array([maximum_speed]))

func _axis_count() -> int:
	return int(enabled_axes.x != 0) + int(enabled_axes.y != 0) + int(enabled_axes.z != 0)

func _refresh_space() -> void:
	space = _expected_space()
	update_configuration_warnings()

func _act(action: Variant) -> void:
	var body := get_node_or_null(body_path) as CharacterBody3D
	var local := Vector3.ZERO
	var index := 0
	for axis in 3:
		if enabled_axes[axis] != 0:
			local[axis] = action[index] * input_scale
			index += 1
	movement_input.emit(local)
	if is_instance_valid(body) and (movement_enabled or force):
		var frame := body.global_basis.orthonormalized()
		var velocity := frame.transposed() * body.velocity
		for axis in 3:
			if enabled_axes[axis] != 0:
				velocity[axis] = local[axis]
		body.velocity = frame * velocity

func _get_component_errors() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not ScholaComponentSpace.matches(space, _expected_space()):
		warnings.append("Movement space must match enabled_axes and speed bounds; reassign maximum_speed to regenerate it.")
	var body := get_node_or_null(body_path) as CharacterBody3D
	if body == null:
		warnings.append("body_path must reference a CharacterBody3D.")
	else:
		var basis := body.global_basis if body.is_inside_tree() else body.basis
		if not ScholaComponentSpace.is_usable_basis(basis):
			warnings.append("Movement requires a finite body basis that can be normalized.")
		else:
			var frame := basis.orthonormalized()
			var current := frame.transposed() * body.velocity
			var magnitude := maxf(absf(maximum_speed), absf(-maximum_speed if symmetric_bounds else minimum_speed)) * absf(input_scale)
			var world_bound := Vector3.ZERO
			for axis in 3:
				world_bound += frame[axis].abs() * (magnitude if enabled_axes[axis] != 0 else absf(current[axis]))
			if not current.is_finite() or not world_bound.is_finite():
				warnings.append("Configured speeds and existing velocity must produce finite world velocities.")
	if not is_finite(maximum_speed) or (symmetric_bounds and maximum_speed <= 0.0) or (not symmetric_bounds and (not is_finite(minimum_speed) or minimum_speed > maximum_speed)):
		warnings.append("Speed bounds must be finite and ordered; symmetric maximum_speed must be positive.")
	if not is_finite(input_scale):
		warnings.append("input_scale must be finite.")
	elif not (Vector3.ONE * (maximum_speed * input_scale)).is_finite() or (not symmetric_bounds and not (Vector3.ONE * (minimum_speed * input_scale)).is_finite()):
		warnings.append("Scaled speed bounds must fit finite Godot velocities.")
	if _axis_count() == 0:
		warnings.append("Enable at least one movement axis.")
	return warnings
