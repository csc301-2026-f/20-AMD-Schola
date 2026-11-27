# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackEnvironment
extends ScholaEnvironment

signal step_rewarded(reward: float)

@export var maximum_stalled_steps: int = 0 # Zero disables stall endings.
@export var maximum_steps: int = 500 # Zero disables the step limit.
const LOCATION_SCALE := 5.0
const OFF_TRACK_PENALTY := -10.0
const DEFAULT_MAXIMUM_TRACK_DISTANCE := 10.0
const TEST_DRIVE_FLAG := "--race-track-test-drive"
@export var terminate_off_track := true
@export var maximum_track_distance: float = DEFAULT_MAXIMUM_TRACK_DISTANCE
@export var terminate_on_tilt := true
@export var maximum_tilt_degrees: float = 10.0
@export var terminate_on_obstacle := false
@export var random_start := false
@export var random_obstacles := false
@export var test_drive_layout_seed := 0
@export_range(0.0, 1.0) var demo_map_share := 0.0
@export var drift_bonus := 0.5

var _previous_distances: Dictionary[ScholaAgent, float] = {}
var _stalled_steps: Dictionary[ScholaAgent, int] = {}
var _test_drive_episodes := 0

@onready var car: ArcadeVehicle = $Car
@onready var agent: RaceTrackAgent = $Car/Agent


static func is_test_drive() -> bool:
	return TEST_DRIVE_FLAG in OS.get_cmdline_user_args()


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	var test_drive := is_test_drive()
	if random_obstacles:
		agent.track.set_obstacles(_test_drive_layout() if test_drive else _training_layout())
	if random_start and not test_drive:
		agent.place(agent.track.transform_at(_random_start_offset()))
	else:
		agent.place_at_start()
	_start_tracking(agent)


func _test_drive_layout() -> PackedVector2Array:
	var episode := _test_drive_episodes
	_test_drive_episodes += 1
	if episode == 0:
		return agent.track.map_obstacles
	var rng := RandomNumberGenerator.new()
	rng.seed = test_drive_layout_seed + episode - 1
	return agent.track.random_obstacle_layout(rng)


func _training_layout() -> PackedVector2Array:
	if get_rng().randf() < demo_map_share:
		return agent.track.map_obstacles
	return agent.track.random_obstacle_layout(get_rng())


func _start_tracking(racer: RaceTrackAgent) -> void:
	_previous_distances[racer] = racer.track.progress_of(racer.car.global_position)
	_stalled_steps[racer] = 0


func _random_start_offset() -> float:
	var length := agent.track.curve.get_baked_length()
	for attempt in 100:
		var offset := get_rng().randf() * length
		if agent.track.is_clear(offset):
			return offset
	return 0.0


func _get_step_result(stepped: ScholaAgent) -> Variant:
	var racer: RaceTrackAgent = stepped
	var vehicle := racer.car
	var track := racer.track
	var distance_now := track.progress_of(vehicle.global_position)
	var progress := track.offset_between(_previous_distances[racer], distance_now)
	_previous_distances[racer] = distance_now
	var distance_from_track := track.distance_from_center(vehicle.global_position)
	var tilted := vehicle.global_basis.y.normalized().dot(Vector3.UP) < cos(deg_to_rad(maximum_tilt_degrees))
	_stalled_steps[racer] = _stalled_steps[racer] + 1 if progress < 0.005 else 0
	var stalled := maximum_stalled_steps > 0 and _stalled_steps[racer] >= maximum_stalled_steps
	var touching: Array = vehicle.get_colliding_bodies() if vehicle.contact_monitor else []
	var hit_obstacle := terminate_on_obstacle and touching.any(func(body: Node) -> bool: return body.is_in_group("obstacle"))
	var off_track := terminate_off_track and (distance_from_track >= maximum_track_distance or touching.any(func(body: Node) -> bool: return body.is_in_group("wall")))
	var flipped := terminate_on_tilt and tilted
	var terminated := stalled or hit_obstacle or off_track or flipped
	var drift := vehicle.drift_amount
	var reward := 0.01 * exp(-pow(distance_from_track / LOCATION_SCALE, 2.0)) + progress * (1.0 + drift_bonus * drift)
	if terminated:
		reward = OFF_TRACK_PENALTY
	step_rewarded.emit(reward)
	return {
		"reward": reward,
		"terminated": terminated,
		"truncated": maximum_steps > 0 and get_episode_step() + 1 >= maximum_steps,
		"info": {"progress": str(progress), "drift": str(drift)},
	}
