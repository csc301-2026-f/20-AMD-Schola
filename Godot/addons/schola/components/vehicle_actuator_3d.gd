# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaVehicleActuator3D
extends ScholaActuator

@export var controls_scale: float = 1.0
@export var maximum_steering_degrees: float = 40.0
@export var maximum_engine_force: float = 7500.0
@export var maximum_brake: float = 30.0
@export var steering_rise_rate: float = 2.5
@export var steering_fall_rate: float = 5.0
@export var pedal_rise_rate: float = 6.0
@export var pedal_fall_rate: float = 10.0
## Steering sign depends on the vehicle orientation and wheel setup.
@export_enum("Negative:-1", "Positive:1") var steering_sign: int = -1
## Zero disables speed-sensitive steering / the engine speed cap.
@export var steering_speed_reference: float = 0.0
@export_range(0.05, 1.0) var minimum_steering_fraction: float = 0.25
@export var top_speed: float = 0.0
@export var body_path: NodePath
var _steering := 0.0
var _throttle := 0.0
var _brake := 0.0

func _init() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([2])
	box.low = PackedFloat32Array([-1.0])
	box.high = PackedFloat32Array([1.0])
	space = box

func reset() -> void:
	_steering = 0.0
	_throttle = 0.0
	_brake = 0.0
	_apply()

func _act(action: Variant) -> void:
	var values: PackedFloat32Array = action
	var steering := clampf(clampf(values[0], -1.0, 1.0) * controls_scale, -1.0, 1.0)
	var pedal := clampf(values[1], -1.0, 1.0) * controls_scale
	var delta := get_physics_process_delta_time()
	_steering = _approach(_steering, steering, steering_rise_rate, steering_fall_rate, delta)
	_throttle = _approach(_throttle, clampf(pedal, 0.0, 1.0), pedal_rise_rate, pedal_fall_rate, delta)
	_brake = _approach(_brake, clampf(-pedal, 0.0, 1.0), pedal_rise_rate, pedal_fall_rate, delta)
	_apply()


func _apply() -> void:
	var car := get_node(body_path) as VehicleBody3D
	var speed := car.linear_velocity.length()
	var steering_fraction := 1.0
	if steering_speed_reference > 0.0:
		steering_fraction = lerpf(1.0, minimum_steering_fraction, clampf(speed / steering_speed_reference, 0.0, 1.0))
	car.steering = steering_sign * _steering * deg_to_rad(maximum_steering_degrees) * steering_fraction
	car.engine_force = _throttle * maximum_engine_force * (clampf(1.0 - pow(speed / top_speed, 4.0), 0.0, 1.0) if top_speed > 0.0 else 1.0)
	car.brake = _brake * maximum_brake


func _approach(current: float, target: float, rise_rate: float, fall_rate: float, delta: float) -> float:
	var rising := absf(target) > absf(current) and signf(target) * signf(current) >= 0.0
	return move_toward(current, target, (rise_rate if rising else fall_rate) * delta)


func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(minimum_steering_fraction) or minimum_steering_fraction < 0.05 or minimum_steering_fraction > 1.0:
		errors.append("minimum_steering_fraction must be between 0.05 and 1.")
	if steering_sign != -1 and steering_sign != 1:
		errors.append("steering_sign must be -1 or 1.")
	if not get_node_or_null(body_path) is VehicleBody3D:
		errors.append("body_path must reference a VehicleBody3D.")
	for value in [steering_speed_reference, top_speed, controls_scale, maximum_steering_degrees, maximum_engine_force, maximum_brake, steering_rise_rate, steering_fall_rate, pedal_rise_rate, pedal_fall_rate]:
		if not is_finite(value) or value < 0.0:
			errors.append("Vehicle gains, limits, and smoothing rates must be finite and nonnegative.")
			break
	return errors
