# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends VehicleBody3D

## Flat-track arcade grip. Wheel contacts still own acceleration and collision response.
@export var lateral_grip: float = 6.0
@export var downforce: float = 1.5

func _physics_process(_delta: float) -> void:
	var grounded := false
	for child in get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			grounded = true
	if not grounded:
		return
	var sideways := global_basis.x
	apply_central_force(-sideways * linear_velocity.dot(sideways) * mass * lateral_grip)
	apply_central_force(Vector3.DOWN * linear_velocity.length() * mass * downforce)
