@tool
class_name GridArena
extends Node2D
## The grid level, drawn in 2D. Cell (x, y) is the square at local (x, y) * cell_size.

const FLOOR := "floor"
const GOAL := "goal"
const HAZARD := "hazard"

const FLOOR_COLOR := Color(0.17, 0.175, 0.2)
const OUTCOME_STYLE := {
	"success": ["GOAL REACHED", Color(0.3, 0.85, 0.4)],
	"failure": ["HIT HAZARD", Color(0.95, 0.3, 0.3)],
	"timeout": ["TIMEOUT", Color(0.95, 0.65, 0.2)],
}

@export var grid_size := Vector2i(6, 6):
	set(value):
		grid_size = value
		queue_redraw()
		update_configuration_warnings()
@export var cell_size := 64.0:
	set(value):
		cell_size = value
		queue_redraw()
## At runtime the board scales and centers itself inside this Control.
@export var fit_to: Control
@export var fit_margin := 24.0

@onready var _banner: Label = $Banner

var _banner_tween: Tween
var _flash_color := Color.TRANSPARENT
var _flash := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_banner.modulate.a = 0.0
	if fit_to != null:
		fit_to.resized.connect(_fit)
		_fit.call_deferred()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.5)
		queue_redraw()


func get_goal_cell() -> Vector2i:
	for marker in _markers(GridMarker.Kind.GOAL):
		return cell_of(marker.position)
	return Vector2i(-1, -1)


func get_hazard_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for marker in _markers(GridMarker.Kind.HAZARD):
		cells.append(cell_of(marker.position))
	return cells


func get_cell_kind(cell: Vector2i) -> String:
	if cell == get_goal_cell():
		return GOAL
	if get_hazard_cells().has(cell):
		return HAZARD
	return FLOOR


func random_free_cell(rng: RandomNumberGenerator) -> Vector2i:
	var free: Array[Vector2i] = []
	for y in grid_size.y:
		for x in grid_size.x:
			if get_cell_kind(Vector2i(x, y)) == FLOOR:
				free.append(Vector2i(x, y))
	return free[rng.randi_range(0, free.size() - 1)]


func clamp_cell(cell: Vector2i) -> Vector2i:
	return cell.clamp(Vector2i.ZERO, grid_size - Vector2i.ONE)


func cell_of(local_position: Vector2) -> Vector2i:
	return Vector2i(floori(local_position.x / cell_size), floori(local_position.y / cell_size))


func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


func tile_rect(cell: Vector2i) -> Rect2:
	var gap := cell_size * 0.06
	return Rect2(Vector2(cell) * cell_size + Vector2(gap, gap) / 2, Vector2(cell_size - gap, cell_size - gap))


func show_outcome(outcome: String, total_reward: float) -> void:
	var style: Array = OUTCOME_STYLE.get(outcome, ["DONE", Color.WHITE])
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.text = "%s\n%+.1f" % [style[0], total_reward]
	_banner.add_theme_color_override("font_color", style[1])
	_banner.modulate.a = 1.0
	_flash_color = style[1]
	_flash = 1.0
	queue_redraw()


func hide_outcome() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.2)


func _draw() -> void:
	for y in grid_size.y:
		for x in grid_size.x:
			draw_rect(tile_rect(Vector2i(x, y)), FLOOR_COLOR)
	if _flash > 0.0:
		var width := cell_size * 0.05
		draw_rect(Rect2(Vector2.ZERO, Vector2(grid_size) * cell_size).grow(width * 1.5), Color(_flash_color, _flash), false, width)


func _fit() -> void:
	var area := fit_to.get_global_rect().grow(-fit_margin)
	var board := Vector2(grid_size) * cell_size
	var fit := minf(area.size.x / board.x, area.size.y / board.y)
	scale = Vector2(fit, fit)
	global_position = area.position + (area.size - board * fit) / 2


func _markers(kind: GridMarker.Kind) -> Array[GridMarker]:
	var markers: Array[GridMarker] = []
	for child in get_children():
		if child is GridMarker and child.kind == kind:
			markers.append(child)
	return markers


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var goals := _markers(GridMarker.Kind.GOAL)
	if goals.size() != 1:
		warnings.append("Add exactly one GridMarker with kind Goal (found %d)." % goals.size())
	for child in get_children():
		if child is GridMarker:
			var cell := cell_of(child.position)
			if cell != clamp_cell(cell):
				warnings.append("%s is outside the %dx%d grid." % [child.name, grid_size.x, grid_size.y])
	return warnings
