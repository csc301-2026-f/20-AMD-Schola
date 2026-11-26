# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Label

@export var environment_path: NodePath
@onready var environment: RaceTrackMultiAgentEnvironment = get_node(environment_path)


func _process(_delta: float) -> void:
	var lines := PackedStringArray(["MULTI-AGENT TRAINING"])
	for racer: RaceTrackAgent in environment.returns:
		var state := "%d km/h" % roundi(racer.car.linear_velocity.length() * 3.6) if environment.racing[racer] else "OUT"
		lines.append("%s: reward %.0f, %s" % [racer.get_resolved_agent_id().to_upper().replace("_", " "), environment.returns[racer], state])
	text = "\n".join(lines)
