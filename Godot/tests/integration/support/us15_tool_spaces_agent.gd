# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
extends ScholaAgent


# Deliberately malformed: warning queries must never execute or validate this.
func _define_observation_space() -> ScholaSpace:
	set_meta("definition_calls", int(get_meta("definition_calls", 0)) + 1)
	return null


func _define_action_space() -> ScholaSpace:
	set_meta("definition_calls", int(get_meta("definition_calls", 0)) + 1)
	return null
