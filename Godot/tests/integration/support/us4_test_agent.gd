# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends ScholaAgent

var observation := 0
var last_action: Variant


func _observe() -> Variant:
	return observation


func _act(action: Variant) -> void:
	last_action = action
	observation = int(action)
