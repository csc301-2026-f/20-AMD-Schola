# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# One agent on the number line 0..LAST. The two control styles give the two
# agents different action spaces, as US12 requires:
#   STEP:    Discrete(3) action, 0 = back, 1 = stay, 2 = forward.
#   BUTTONS: MultiBinary(2) action, [back pressed, forward pressed].
# The observation space is set on the node in main.tscn and must match what
# _observe() returns: see observes_partner.
extends ScholaAgent

const LAST := 9

enum Controls { STEP, BUTTONS }

@export var controls := Controls.STEP
# True: observe Box(2) [own position, partner position], scaled to 0..1.
# False: observe Discrete(10), the agent's own position.
@export var observes_partner := false

var position := 0
# Position before this step's action, so the environment can reward progress.
var previous_position := 0
# Episode step this agent last acted on. A finished agent stops acting, so this
# tells the environment which agents are still in the episode.
var acted_on_step := -1


func _observe() -> Variant:
	if not observes_partner:
		return position
	return PackedFloat32Array([position / float(LAST), _partner_position() / float(LAST)])


func _act(action: Variant) -> void:
	previous_position = position
	acted_on_step = get_parent().get_episode_step()
	var move := 0
	if controls == Controls.STEP:
		move = int(action) - 1
	else:
		move = int(action[1]) - int(action[0])
	position = clampi(position + move, 0, LAST)


func reached_goal() -> bool:
	return position == LAST


func _partner_position() -> int:
	for agent in get_parent().get_agents():
		if agent != self:
			return agent.position
	return 0
