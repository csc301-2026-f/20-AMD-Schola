class_name RaceTrackEnvironment
extends ScholaEnvironment

const MAX_STEP_COUNT := 500
const LOCATION_SCALE := 5.0
const OFF_TRACK_PENALTY := -10.0
const TOO_FAR_FROM_TRACK := 10.0
const MAX_ROLL_DEGREES := 10.0

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
	var terminated := distance_from_track >= TOO_FAR_FROM_TRACK or absf(rad_to_deg(car.global_rotation.z)) > MAX_ROLL_DEGREES
	var reward := 0.01 * exp(-pow(distance_from_track / LOCATION_SCALE, 2.0)) + progress
	return {
		"reward": OFF_TRACK_PENALTY if terminated else reward,
		"terminated": terminated,
		"truncated": get_episode_step() + 1 >= MAX_STEP_COUNT,
	}
