class_name RaceTrackEnvironment
extends ScholaEnvironment

@export var maximum_steps: int = 500 # Zero disables the step limit.
const LOCATION_SCALE := 5.0
const OFF_TRACK_PENALTY := -10.0
@export var terminate_off_track := true
@export var maximum_track_distance: float = 10.0
@export var terminate_on_tilt := true
@export var maximum_tilt_degrees: float = 10.0

var _previous_distance := 0.0

@onready var car: VehicleBody3D = $Car
@onready var agent: RaceTrackAgent = $Car/Agent


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	agent.place_at_start()
	_previous_distance = agent.track.progress_of(car.global_position)


func _get_step_result(_agent: ScholaAgent) -> Variant:
	var track := agent.track
	var distance_now := track.progress_of(car.global_position)
	var progress := distance_now - _previous_distance
	_previous_distance = distance_now
	var distance_from_track := track.distance_from_center(car.global_position)
	var tilted := car.global_basis.y.normalized().dot(Vector3.UP) < cos(deg_to_rad(maximum_tilt_degrees))
	var terminated := (terminate_off_track and distance_from_track >= maximum_track_distance) or (terminate_on_tilt and tilted)
	var reward := 0.01 * exp(-pow(distance_from_track / LOCATION_SCALE, 2.0)) + progress
	return {
		"reward": OFF_TRACK_PENALTY if terminated else reward,
		"terminated": terminated,
		"truncated": maximum_steps > 0 and get_episode_step() + 1 >= maximum_steps,
	}
