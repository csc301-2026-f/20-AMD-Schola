# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends ScholaEnvironment

class TestAgent extends ScholaAgent:
	func _observe() -> Variant:
		return PackedFloat32Array([0.0])

	func _act(_action: Variant) -> void:
		pass

var _templates: Array[ScholaAgent] = []
var _reset_count := 0


func _ready() -> void:
	for id in ["a", "b"]:
		var agent := TestAgent.new()
		var observations := ScholaBoxSpace.new()
		observations.shape = PackedInt32Array([1])
		observations.low = PackedFloat32Array([-1.0])
		observations.high = PackedFloat32Array([1.0])
		var actions := ScholaDiscreteSpace.new()
		actions.n = 2
		agent.agent_id = id
		agent.agent_type = "default"
		agent.observation_space = observations
		agent.action_space = actions
		_templates.append(agent)


func _exit_tree() -> void:
	for agent in _templates:
		agent.free()


func _get_possible_agents() -> Array[ScholaAgent]:
	return _templates


func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
	for agent in get_agents():
		remove_child(agent)
		agent.queue_free()
	_reset_count += 1
	for index in range(1 if _reset_count % 2 == 1 else 2):
		var template := _templates[index]
		var agent := TestAgent.new()
		agent.agent_id = template.agent_id
		agent.agent_type = template.agent_type
		agent.observation_space = template.observation_space
		agent.action_space = template.action_space
		add_child(agent)


func _physics_process(_delta: float) -> void:
	# Frames advance between connector requests, even with no ready agents.
	if get_episode_step() == 3:
		for agent in get_agents():
			agent.training_paused = false


func _get_step_result(agent: ScholaAgent) -> Dictionary:
	var step := get_episode_step()
	if step == 0:
		agent.training_paused = true
	return {"reward": 1.0, "terminated": step == 4}
