extends Node2D

## Scene-owned integration hooks for the D2 demo.
## These placeholders define the shape expected by the plugin integration. They do
## not implement an environment, a connector, or a training policy.

func get_observation() -> PackedFloat32Array:
	return PackedFloat32Array()


func apply_action(_action: int) -> void:
	pass


func get_step_result() -> Dictionary:
	return {
		"reward": 0.0,
		"terminated": false,
		"truncated": false,
	}


func reset_episode() -> void:
	pass
