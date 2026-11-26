# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackMultiAgentEnvironment
extends RaceTrackEnvironment

@export var start_spacing := 20.0

var returns: Dictionary[ScholaAgent, float] = {}
var racing: Dictionary[ScholaAgent, bool] = {}
var _distances: Dictionary[ScholaAgent, float] = {}
var _stalls: Dictionary[ScholaAgent, int] = {}


func _reset_episode(seed: Variant, options: Dictionary) -> void:
	var racers := get_agents()
	for racer: RaceTrackAgent in racers:
		_set_racing(racer, true)
	agent = racers[0]
	car = agent.car
	super(seed, options)
	var length := agent.track.curve.get_baked_length()
	var start := agent.track.progress_of(car.global_position)
	for index in racers.size():
		var racer: RaceTrackAgent = racers[index]
		if index > 0:
			racer.place(agent.track.transform_at(fposmod(start + index * start_spacing, length)))
		returns[racer] = 0.0
		_stalls[racer] = 0
		_distances[racer] = agent.track.progress_of(racer.car.global_position)
	_show(racers[0])


func _clear_offset() -> float:
	var track := agent.track
	var length := track.curve.get_baked_length()
	for attempt in 200:
		var offset := get_rng().randf() * length
		var clear := true
		for index in get_agents().size():
			clear = clear and track.is_clear(fposmod(offset + index * start_spacing, length))
		if clear:
			return offset
	return 0.0


func _get_step_result(stepped: ScholaAgent) -> Variant:
	agent = stepped
	car = agent.car
	_previous_distance = _distances[agent]
	_stalled_steps = _stalls[agent]
	var result: Dictionary = super(stepped)
	_distances[agent] = _previous_distance
	_stalls[agent] = _stalled_steps
	returns[agent] += result.reward
	result.info.agent = agent.get_resolved_agent_id()
	if result.terminated or result.truncated:
		_retire.call_deferred(agent, get_episode_step())
	return result


func _retire(racer: RaceTrackAgent, episode_step: int) -> void:
	if get_episode_step() < episode_step:
		return
	_set_racing(racer, false)
	for child in racer.rays.get_children(true):
		child.visible = false
	for other: RaceTrackAgent in get_agents():
		if racing[other]:
			_show(other)
			return


func _set_racing(racer: RaceTrackAgent, value: bool) -> void:
	racing[racer] = value
	racer.car.visible = value
	racer.car.freeze = not value
	racer.car.set_physics_process(value)
	racer.car.collision_layer = 1 if value else 0
	racer.car.collision_mask = 1 if value else 0


func _show(racer: RaceTrackAgent) -> void:
	(racer.car.get_node("Camera") as Camera3D).make_current()
