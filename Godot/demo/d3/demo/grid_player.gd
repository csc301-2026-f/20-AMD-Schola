@tool
class_name GridPlayer
extends Node2D
## The agent's body: tracks its cell, draws itself, and animates moves.

const COLOR := Color(0.36, 0.6, 1.0)
const RADIUS := 0.3

var cell := Vector2i.ZERO
var _move_tween: Tween


func get_arena() -> GridArena:
	return get_parent() as GridArena


func move(p_direction: Vector2i) -> void:
	var arena := get_arena()
	cell = arena.clamp_cell(cell + p_direction)
	_slide_to(arena.cell_center(cell))


func place(p_cell: Vector2i) -> void:
	cell = p_cell
	if _move_tween != null:
		_move_tween.kill()
	position = get_arena().cell_center(cell)
	scale = Vector2.ONE * 0.3
	_move_tween = create_tween()
	_move_tween.tween_property(self, "scale", Vector2.ONE, 0.15)


func _draw() -> void:
	var arena := get_arena()
	var size := arena.cell_size if arena != null else 64.0
	draw_circle(Vector2.ZERO, size * RADIUS, COLOR, true, -1.0, true)


func _slide_to(target: Vector2) -> void:
	if _move_tween != null:
		_move_tween.kill()
	scale = Vector2.ONE
	var duration := 0.12
	var runner := get_tree().get_first_node_in_group(ScholaDemoRunner.GROUP) as ScholaDemoRunner
	if runner != null:
		duration = minf(0.12, 0.8 / runner.steps_per_second)
	if duration < 0.02:
		position = target
		return
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
