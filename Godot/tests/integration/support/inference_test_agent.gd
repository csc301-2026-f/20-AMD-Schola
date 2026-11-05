# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends ScholaAgent

var observation: Variant
var actions: Array = []
var on_observe := Callable()
var on_act := Callable()


func setup(observation_size: int, action_size: int, value: Variant) -> void:
	observation_space = _box(observation_size)
	action_space = _box(action_size)
	observation = value


func _observe() -> Variant:
	if on_observe.is_valid():
		on_observe.call()
	return observation


func _act(action: Variant) -> void:
	actions.append(action)
	if on_act.is_valid():
		on_act.call()


func _box(size: int) -> ScholaBoxSpace:
	var space := ScholaBoxSpace.new()
	var low := PackedFloat32Array()
	var high := PackedFloat32Array()
	for i in size:
		low.append(-10.0)
		high.append(10.0)
	space.low = low
	space.high = high
	space.shape = PackedInt32Array([size])
	return space
