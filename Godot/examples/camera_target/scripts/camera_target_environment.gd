# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name CameraTargetEnvironment
extends ScholaEnvironment

@export var ball_distance: float = 4.0
@export var maximum_ball_angle: float = 30.0
@export var maximum_steps: int = 100

@onready var body: Node3D = $Agent/Body
@onready var ball: Node3D = $Ball


func _reset_episode(episode_seed: Variant, _options: Dictionary) -> void:
	if episode_seed is int:
		get_rng().seed = episode_seed
	body.rotation = Vector3.ZERO
	place_ball()


func place_ball() -> void:
	var angle := deg_to_rad(get_rng().randf_range(-maximum_ball_angle, maximum_ball_angle))
	ball.global_position = body.global_position + _flat_forward().rotated(Vector3.UP, angle) * ball_distance


func _get_step_result(_agent: ScholaAgent) -> Variant:
	return {
		"reward": facing(),
		"truncated": get_episode_step() + 1 >= maximum_steps,
	}


func facing() -> float:
	var to_ball := ball.global_position - body.global_position
	to_ball.y = 0.0
	return _flat_forward().dot(to_ball.normalized())


func _flat_forward() -> Vector3:
	var forward := -body.global_basis.z
	forward.y = 0.0
	return forward.normalized()
