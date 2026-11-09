class_name RaceTrackAgent
extends ScholaAgent

const LOCATION_SCALE := 5.0
const VELOCITY_SCALE := 2.0
const CAR_CONTROLS_SCALE := 100.0
const MAX_STEERING_DEGREES := 40.0
const MAX_ENGINE_FORCE := 7500.0
const MAX_BRAKE := 30.0
const STEERING_RISE_RATE := 2.5
const STEERING_FALL_RATE := 5.0
const PEDAL_RISE_RATE := 6.0
const PEDAL_FALL_RATE := 10.0

var track: RaceTrackPath
var _steering := 0.0
var _throttle := 0.0
var _brake := 0.0

@onready var car: VehicleBody3D = get_parent()


func _ready() -> void:
	track = RaceTrackPath.find_in(get_tree())
	place_at_start()


func place_at_start() -> void:
	car.global_transform = track.start_transform()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	_steering = 0.0
	_throttle = 0.0
	_brake = 0.0
	_apply()


func _observe() -> Variant:
	var offset := track.progress_of(car.global_position)
	var to_car_frame := car.global_basis.inverse()
	var track_location := _forward_right_up(to_car_frame * (track.center_at(offset) - car.global_position)) / LOCATION_SCALE
	var track_direction := _forward_right_up(to_car_frame * track.direction_at(offset))
	var velocity := _forward_right_up(to_car_frame * car.linear_velocity) / VELOCITY_SCALE
	return PackedFloat32Array([
		track_location.x, track_location.y, track_location.z,
		track_direction.x, track_direction.y, track_direction.z,
		velocity.x, velocity.y, velocity.z, 0.0,
	])


func _act(action: Variant) -> void:
	var values: PackedFloat32Array = action
	var steering := clampf(clampf(values[0], -1.0, 1.0) * CAR_CONTROLS_SCALE, -1.0, 1.0)
	var pedal := clampf(values[1], -1.0, 1.0) * CAR_CONTROLS_SCALE
	var delta := get_physics_process_delta_time()
	_steering = _approach(_steering, steering, STEERING_RISE_RATE, STEERING_FALL_RATE, delta)
	_throttle = _approach(_throttle, clampf(pedal, 0.0, 1.0), PEDAL_RISE_RATE, PEDAL_FALL_RATE, delta)
	_brake = _approach(_brake, clampf(-pedal, 0.0, 1.0), PEDAL_RISE_RATE, PEDAL_FALL_RATE, delta)
	_apply()


func _apply() -> void:
	car.steering = -_steering * deg_to_rad(MAX_STEERING_DEGREES)
	car.engine_force = _throttle * MAX_ENGINE_FORCE
	car.brake = _brake * MAX_BRAKE


func _approach(current: float, target: float, rise_rate: float, fall_rate: float, delta: float) -> float:
	var rising := absf(target) > absf(current) and signf(target) * signf(current) >= 0.0
	return move_toward(current, target, (rise_rate if rising else fall_rate) * delta)


func _forward_right_up(local: Vector3) -> Vector3:
	return Vector3(local.z, -local.x, local.y)
