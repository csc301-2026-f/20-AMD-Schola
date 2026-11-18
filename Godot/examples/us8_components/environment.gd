# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends ScholaEnvironment

@onready var body: CharacterBody3D = $Agent/Body

func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	body.position = Vector3(0, 0.5, 3)
	body.velocity = Vector3.ZERO

func _get_step_result(_agent: ScholaAgent) -> Variant:
	return {"reward": 0.0}
