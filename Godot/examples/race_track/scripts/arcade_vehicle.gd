# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends VehicleBody3D

## Flat-track arcade grip with a mild brake-and-turn drift assist.
@export var lateral_grip: float = 6.0
@export var downforce: float = 1.5
@export var drift_minimum_speed: float = 7.0
@export var drift_grip_fraction: float = 0.4
@export var drift_rear_tire_fraction: float = 0.65
@export var drift_yaw_assist: float = 6.0
@export var drift_maximum_yaw_speed: float = 1.2
var drift_amount := 0.0
var _rear_grip: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is VehicleWheel3D and child.use_as_traction and not child.use_as_steering:
			_rear_grip[child] = child.wheel_friction_slip

func reset_handling() -> void:
	drift_amount = 0.0
	_restore_tire_grip()

func _update_drift(delta: float, grounded: bool) -> void:
	var speed := linear_velocity.dot(global_basis.z)
	var wants_drift := grounded and speed >= drift_minimum_speed and brake > 1.0 and absf(steering) > 0.035
	drift_amount = move_toward(drift_amount, 1.0 if wants_drift else 0.0, delta * (3.0 if wants_drift else 2.0))
	_restore_tire_grip()

func _restore_tire_grip() -> void:
	for wheel in _rear_grip:
		wheel.wheel_friction_slip = _rear_grip[wheel] * lerpf(1.0, drift_rear_tire_fraction, drift_amount)

func _physics_process(delta: float) -> void:
	var grounded := false
	for child in get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			grounded = true
	_update_drift(delta, grounded)
	if not grounded:
		return
	var sideways := global_basis.x
	var grip := lateral_grip * lerpf(1.0, drift_grip_fraction, drift_amount)
	apply_central_force(-sideways * linear_velocity.dot(sideways) * mass * grip)
	apply_central_force(Vector3.DOWN * linear_velocity.length() * mass * downforce)
	# Ease out the assist near the yaw limit rather than clamping physical rotation.
	var yaw_margin := clampf(1.0 - absf(angular_velocity.y) / maxf(drift_maximum_yaw_speed, 0.01), 0.0, 1.0)
	apply_torque(Vector3.UP * steering * mass * drift_yaw_assist * drift_amount * yaw_margin)
