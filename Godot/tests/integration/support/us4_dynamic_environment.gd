# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends "res://tests/integration/support/us4_test_environment.gd"

var definitions: Array[ScholaAgent] = []

func _get_possible_agents() -> Array[ScholaAgent]:
	return definitions
