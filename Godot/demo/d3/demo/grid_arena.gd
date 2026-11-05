# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

@tool
class_name GridArena
extends Node2D
## The grid level, drawn in 2D. Cell (x, y) is the square at local (x, y) * cell_size.
## A map is {"size": [w, h], "goal": [x, y], "hazards": [[x, y], ...]}. While editing, left click or
## drag toggles hazards and right click moves the goal.

signal map_changed

const FLOOR := "floor"
const GOAL := "goal"
const HAZARD := "hazard"

const FLOOR_COLOR := Color(0.17, 0.175, 0.2)
const HOVER_COLOR := Color(1, 1, 1, 0.12)
const MIN_SIZE := 3
const MAX_SIZE := 10
const RANDOM_HAZARD_SHARE := 0.15
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
var _editing := false
var _hover := Vector2i(-1, -1)
var _paint := -1


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


func get_map() -> Dictionary:
	var goal := get_goal_cell()
	var hazards := []
	for cell in get_hazard_cells():
		hazards.append([cell.x, cell.y])
	hazards.sort()
	return {"size": [grid_size.x, grid_size.y], "goal": [goal.x, goal.y], "hazards": hazards}


## Returns an error message, or "" when the map is usable.
static func validate_map(map: Dictionary) -> String:
	var size: Variant = map.get("size")
	if typeof(size) != TYPE_ARRAY or size.size() != 2:
		return "map size must be [width, height]"
	var width := int(size[0])
	var height := int(size[1])
	if width < MIN_SIZE or height < MIN_SIZE or width > MAX_SIZE or height > MAX_SIZE:
		return "map size must be between %d and %d cells per side" % [MIN_SIZE, MAX_SIZE]
	var inside := func(cell: Variant) -> bool:
		return typeof(cell) == TYPE_ARRAY and cell.size() == 2 and int(cell[0]) >= 0 and int(cell[1]) >= 0 and int(cell[0]) < width and int(cell[1]) < height
	if not inside.call(map.get("goal")):
		return "the goal must be inside the grid"
	var hazards: Variant = map.get("hazards", [])
	if typeof(hazards) != TYPE_ARRAY:
		return "hazards must be a list of cells"
	for hazard in hazards:
		if not inside.call(hazard):
			return "hazard %s is outside the grid" % [hazard]
		if int(hazard[0]) == int(map.goal[0]) and int(hazard[1]) == int(map.goal[1]):
			return "a hazard cannot share the goal's cell"
	if hazards.size() >= width * height - 1:
		return "leave at least one free cell besides the goal"
	return ""


## Replaces the grid size and markers. The map must pass validate_map().
func apply_map(map: Dictionary) -> void:
	for child in get_children():
		if child is GridMarker:
			remove_child(child)
			child.queue_free()
	grid_size = Vector2i(int(map.size[0]), int(map.size[1]))
	_add_marker(GridMarker.Kind.GOAL, Vector2i(int(map.goal[0]), int(map.goal[1])))
	for hazard in map.get("hazards", []):
		_add_marker(GridMarker.Kind.HAZARD, Vector2i(int(hazard[0]), int(hazard[1])))
	_banner.size = Vector2(grid_size) * cell_size
	for child in get_children():
		if child is GridPlayer:
			child.place(clamp_cell(child.cell))
	if fit_to != null and not Engine.is_editor_hint():
		_fit()
	queue_redraw()
	map_changed.emit()


## Free cells from which the goal cannot be reached without crossing a hazard.
func unreachable_cells() -> Array[Vector2i]:
	var goal := get_goal_cell()
	var reached := {goal: true}
	var queue: Array[Vector2i] = [goal]
	var hazards := get_hazard_cells()
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if next == clamp_cell(next) and not reached.has(next) and not hazards.has(next):
				reached[next] = true
				queue.append(next)
	var unreachable: Array[Vector2i] = []
	for y in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, y)
			if not reached.has(cell) and not hazards.has(cell):
				unreachable.append(cell)
	return unreachable


func set_editing(p_editing: bool) -> void:
	_editing = p_editing
	_hover = Vector2i(-1, -1)
	for child in get_children():
		if child is GridPlayer:
			child.visible = not p_editing
	_banner.modulate.a = 0.0
	queue_redraw()


## Changes the grid size, keeping the markers that still fit and moving the goal inside if needed.
func resize_map(delta: Vector2i) -> void:
	var size := (grid_size + delta).clamp(Vector2i(MIN_SIZE, MIN_SIZE), Vector2i(MAX_SIZE, MAX_SIZE))
	var map := get_map()
	map.size = [size.x, size.y]
	var goal := Vector2i(map.goal[0], map.goal[1]).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	map.goal = [goal.x, goal.y]
	map.hazards = map.hazards.filter(func(cell: Array) -> bool:
		return cell[0] < size.x and cell[1] < size.y and Vector2i(cell[0], cell[1]) != goal)
	apply_map(map)


## A random goal and hazards that keep every free cell connected to the goal.
func randomize_map(rng: RandomNumberGenerator) -> void:
	var goal := Vector2i(rng.randi_range(0, grid_size.x - 1), rng.randi_range(0, grid_size.y - 1))
	apply_map({"size": [grid_size.x, grid_size.y], "goal": [goal.x, goal.y], "hazards": []})
	var target := roundi(grid_size.x * grid_size.y * RANDOM_HAZARD_SHARE)
	var placed := 0
	for attempt in grid_size.x * grid_size.y * 4:
		if placed >= target:
			break
		var cell := Vector2i(rng.randi_range(0, grid_size.x - 1), rng.randi_range(0, grid_size.y - 1))
		if get_cell_kind(cell) != FLOOR:
			continue
		var marker := _add_marker(GridMarker.Kind.HAZARD, cell)
		if unreachable_cells().is_empty():
			placed += 1
		else:
			remove_child(marker)
			marker.queue_free()
	queue_redraw()
	map_changed.emit()


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


func _unhandled_input(event: InputEvent) -> void:
	if not _editing:
		return
	if event is InputEventMouseMotion:
		var cell := cell_of(get_local_mouse_position())
		var hover := cell if cell == clamp_cell(cell) else Vector2i(-1, -1)
		if hover != _hover:
			_hover = hover
			queue_redraw()
			if _paint != -1 and hover.x != -1:
				_set_hazard(hover, _paint == 1)
	elif event is InputEventMouseButton:
		var cell := cell_of(get_local_mouse_position())
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_paint = -1
			return
		if cell != clamp_cell(cell):
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_paint = 0 if get_cell_kind(cell) == HAZARD else 1
			_set_hazard(cell, _paint == 1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_set_hazard(cell, false)
			for marker in _markers(GridMarker.Kind.GOAL):
				marker.position = cell_center(cell)
			map_changed.emit()
			get_viewport().set_input_as_handled()


func _set_hazard(cell: Vector2i, hazard: bool) -> void:
	if cell == get_goal_cell():
		return
	var existing: GridMarker = null
	for marker in _markers(GridMarker.Kind.HAZARD):
		if cell_of(marker.position) == cell:
			existing = marker
	if hazard and existing == null:
		_add_marker(GridMarker.Kind.HAZARD, cell)
	elif not hazard and existing != null:
		remove_child(existing)
		existing.queue_free()
	else:
		return
	map_changed.emit()


func _add_marker(kind: GridMarker.Kind, cell: Vector2i) -> GridMarker:
	var marker := GridMarker.new()
	marker.kind = kind
	marker.name = "Goal" if kind == GridMarker.Kind.GOAL else "Hazard"
	marker.position = cell_center(cell)
	add_child(marker, true)
	# Markers draw under the player and the banner.
	move_child(marker, 0)
	return marker


func _draw() -> void:
	for y in grid_size.y:
		for x in grid_size.x:
			draw_rect(tile_rect(Vector2i(x, y)), FLOOR_COLOR)
	if _editing and _hover.x != -1:
		draw_rect(tile_rect(_hover), HOVER_COLOR)
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
