# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

@tool
class_name GridMarker
extends Node2D
## Marks the cell under it as the goal or a hazard, and draws that tile.

enum Kind { GOAL, HAZARD }

const COLORS := {
	Kind.GOAL: Color(0.22, 0.72, 0.4),
	Kind.HAZARD: Color(0.78, 0.22, 0.24),
}

@export var kind := Kind.HAZARD:
	set(value):
		kind = value
		queue_redraw()
		update_configuration_warnings()


func _draw() -> void:
	var arena := get_parent() as GridArena
	var size := arena.cell_size if arena != null else 64.0
	var tile := size * 0.94
	draw_rect(Rect2(-Vector2(tile, tile) / 2, Vector2(tile, tile)), COLORS[kind])


func _get_configuration_warnings() -> PackedStringArray:
	if not get_parent() is GridArena:
		return PackedStringArray(["GridMarker must be a child of a GridArena."])
	return PackedStringArray()
