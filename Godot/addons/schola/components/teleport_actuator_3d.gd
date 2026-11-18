# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaTeleportActuator3D
extends ScholaActuator

## Each axis selects from enabled WAIT/POSITIVE/NEGATIVE flags in that order.
## Axes with fewer than two options are omitted, matching Unreal Schola.
signal teleport_input(offset: Vector3)
const WAIT := 1
const POSITIVE := 2
const NEGATIVE := 4

@export var target_path: NodePath:
	set(value):
		target_path = value
		update_configuration_warnings()
@export_flags("Wait", "Positive", "Negative") var x_directions: int = POSITIVE | NEGATIVE:
	set(value):
		x_directions = value
		_refresh_space()
@export_flags("Wait", "Positive", "Negative") var y_directions: int = 0:
	set(value):
		y_directions = value
		_refresh_space()
@export_flags("Wait", "Positive", "Negative") var z_directions: int = 0:
	set(value):
		z_directions = value
		_refresh_space()
@export var step: Vector3 = Vector3.ONE:
	set(value):
		step = value
		update_configuration_warnings()
@export var sweep: bool = false:
	set(value):
		sweep = value
		update_configuration_warnings()

func _init() -> void:
	_refresh_space()

func _options(flags: int) -> PackedInt32Array:
	var options := PackedInt32Array()
	for flag in [WAIT, POSITIVE, NEGATIVE]:
		if flags & flag:
			options.append(flag)
	return options

func _expected_space() -> ScholaMultiDiscreteSpace:
	var result := ScholaMultiDiscreteSpace.new()
	var counts := PackedInt32Array()
	for flags in [x_directions, y_directions, z_directions]:
		var count := _options(flags).size()
		if count >= 2:
			counts.append(count)
	result.nvec = counts
	return result

func _refresh_space() -> void:
	space = _expected_space()
	update_configuration_warnings()

func _act(action: Variant) -> void:
	var offset := Vector3.ZERO
	var directions := [x_directions, y_directions, z_directions]
	var index := 0
	for axis in 3:
		var options := _options(directions[axis])
		if options.size() >= 2:
			var selected := options[action[index]]
			offset[axis] = step[axis] * (1 if selected == POSITIVE else (-1 if selected == NEGATIVE else 0))
			index += 1
	var target := get_node_or_null(target_path) as Node3D
	teleport_input.emit(offset)
	if is_instance_valid(target):
		if sweep:
			(target as PhysicsBody3D).move_and_collide(offset)
		else:
			target.global_position += offset # Unreal's implementation uses world axes.

func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var target := get_node_or_null(target_path)
	if not target is Node3D or target is RigidBody3D:
		errors.append("target_path must reference a Node3D; use a CharacterBody3D for swept movement. RigidBody3D requires its physics integration callback.")
	if sweep and not target is PhysicsBody3D:
		errors.append("sweep requires a PhysicsBody3D target.")
	if target is Node3D:
		var position: Vector3 = target.global_position if target.is_inside_tree() else target.position
		var extent := Vector3.ZERO
		var directions := [x_directions, y_directions, z_directions]
		for axis in 3:
			if _options(directions[axis]).size() >= 2:
				extent[axis] = absf(step[axis])
		if not (position.abs() + extent).is_finite():
			errors.append("Configured steps must keep the target's world position finite.")
	for flags in [x_directions, y_directions, z_directions]:
		if flags < 0 or flags > 7:
			errors.append("Direction flags must use only Wait, Positive and Negative.")
	if not step.is_finite():
		errors.append("step must be finite.")
	if not ScholaComponentSpace.matches(space, _expected_space()):
		errors.append("Teleport space must match its direction flags.")
	return errors
