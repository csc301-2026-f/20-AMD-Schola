# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends ScholaAgent

@export var choice_count := 3
@export var nested := false
@export var joint_count := 3

var definition_calls := 0
var action_definition_calls := 0
var last_spaces: Dictionary
var observation: Variant = 0
var last_action: Variant


func make_spaces() -> Dictionary:
	if not nested:
		return _spaces(
			ScholaSpaces.discrete(choice_count),
			ScholaSpaces.discrete(choice_count),
		)
	var joints := {}
	for index in range(joint_count):
		joints["joint_%d" % index] = ScholaSpaces.dict({
			"angle": ScholaSpaces.box_bounds([2], [-PI, -1], [PI, 1]),
			"contact": ScholaSpaces.multi_binary(2),
		})
	return _spaces(
		ScholaSpaces.dict({
			"camera": ScholaSpaces.box([24, 32, 3], 0, 255, ScholaSpaces.UINT8),
			"joints": ScholaSpaces.dict(joints),
			"mode": ScholaSpaces.multi_discrete([2, 3]),
		}),
		ScholaSpaces.dict({
			"motors": ScholaSpaces.box([joint_count], -1, 1),
			"controls": ScholaSpaces.dict({
				"grip": ScholaSpaces.multi_binary(2),
				"mode": ScholaSpaces.discrete(choice_count),
			}),
		}),
	)


func _define_observation_space() -> ScholaSpace:
	definition_calls += 1
	last_spaces = make_spaces()
	return last_spaces.observation


func _define_action_space() -> ScholaSpace:
	action_definition_calls += 1
	return last_spaces.action


func _observe() -> Variant:
	return observation


func _act(action: Variant) -> void:
	last_action = action


func _spaces(observation: ScholaSpace, action: ScholaSpace) -> Dictionary:
	return {"observation": observation, "action": action}
