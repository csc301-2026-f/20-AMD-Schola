# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackEnvironment
extends ScholaEnvironment

@export var maximum_stalled_steps: int = 0 # Zero disables stall endings.
@export var maximum_steps: int = 500 # Zero disables the step limit.
const LOCATION_SCALE := 5.0
const OFF_TRACK_PENALTY := -10.0
const DEFAULT_MAXIMUM_TRACK_DISTANCE := 10.0
@export var terminate_off_track := true
@export var maximum_track_distance: float = DEFAULT_MAXIMUM_TRACK_DISTANCE
@export var terminate_on_tilt := true
@export var maximum_tilt_degrees: float = 10.0
@export var terminate_on_obstacle := false
@export var random_start := false
@export var random_obstacles := false
@export var test_drive_layout_seed := 0
@export var drift_bonus := 0.5

var _previous_distance := 0.0
var _stalled_steps := 0

@onready var car: VehicleBody3D = $Car
@onready var agent: RaceTrackAgent = $Car/Agent


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	_stalled_steps = 0
	var test_drive := "--race-track-start-line" in OS.get_cmdline_user_args()
	if random_obstacles:
		var rng := get_rng()
		if test_drive:
			rng = RandomNumberGenerator.new()
			rng.seed = test_drive_layout_seed
		agent.track.set_obstacles(agent.track.random_obstacle_layout(rng))
	if random_start and not test_drive:
		agent.place(agent.track.transform_at(_clear_offset()))
	else:
		agent.place_at_start()
	_previous_distance = agent.track.progress_of(car.global_position)


func _clear_offset() -> float:
	var length := agent.track.curve.get_baked_length()
	for attempt in 100:
		var offset := get_rng().randf() * length
		if agent.track.is_clear(offset):
			return offset
	return 0.0


func _get_step_result(_agent: ScholaAgent) -> Variant:
	var track := agent.track
	var distance_now := track.progress_of(car.global_position)
	var track_length := track.curve.get_baked_length()
	var progress := wrapf(distance_now - _previous_distance, -track_length * 0.5, track_length * 0.5)
	_previous_distance = distance_now
	var distance_from_track := track.distance_from_center(car.global_position)
	var tilted := car.global_basis.y.normalized().dot(Vector3.UP) < cos(deg_to_rad(maximum_tilt_degrees))
	_stalled_steps = _stalled_steps + 1 if progress < 0.005 else 0
	var stalled := maximum_stalled_steps > 0 and _stalled_steps >= maximum_stalled_steps
	var hit_obstacle := terminate_on_obstacle and car.get_colliding_bodies().any(func(body: Node) -> bool: return body.is_in_group("obstacle"))
	var off_track := terminate_off_track and distance_from_track >= maximum_track_distance
	var flipped := terminate_on_tilt and tilted
	var terminated := stalled or hit_obstacle or off_track or flipped
	var drift := float(car.get("drift_amount"))
	var reward := 0.01 * exp(-pow(distance_from_track / LOCATION_SCALE, 2.0)) + progress * (1.0 + drift_bonus * drift)
	return {
		"reward": OFF_TRACK_PENALTY if terminated else reward,
		"terminated": terminated,
		"truncated": maximum_steps > 0 and get_episode_step() + 1 >= maximum_steps,
		"info": {"progress": str(progress), "drift": str(drift)},
	}
