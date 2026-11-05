class_name ScholaMiniBoard
extends Control
## Draws one training instance's grid from the reports it sends to the parallel viewer.

const BACKGROUND := Color(0.105, 0.11, 0.13)
const FLOOR := Color(0.17, 0.175, 0.2)
const GOAL := Color(0.22, 0.72, 0.4)
const HAZARD := Color(0.78, 0.22, 0.24)
const AGENT := Color(0.36, 0.6, 1.0)
const TEXT := Color(0.85, 0.86, 0.9)
const MUTED := Color(0.55, 0.57, 0.62)
const OUTCOME_COLORS := {
	"success": Color(0.3, 0.85, 0.4),
	"failure": Color(0.95, 0.3, 0.3),
	"timeout": Color(0.95, 0.65, 0.2),
}
const HEADER_HEIGHT := 18.0

var port := 0
var report := {}
## Shown before the instance's first report.
var placeholder := "idle":
	set(value):
		placeholder = value
		queue_redraw()
## True when the instance has stopped reporting.
var stale := false:
	set(value):
		if stale != value:
			stale = value
			queue_redraw()

var _flash_color := Color.TRANSPARENT
var _flash := 0.0


func set_report(p_report: Dictionary) -> void:
	report = p_report
	var finished: Array = p_report.get("finished", [])
	if not finished.is_empty():
		_flash_color = OUTCOME_COLORS.get(finished[-1][1], MUTED)
		_flash = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, 13), ":%d" % port, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT)
	if report.has("episode"):
		var status := "ep %d · %s" % [int(report.episode), str(report.get("mode", "")).to_lower()]
		draw_string(font, Vector2(0, 13), status, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 10, MUTED)

	var view: Dictionary = report.get("view", {})
	if view.is_empty():
		_draw_centered(font, placeholder)
		return

	var columns: int = view.size[0]
	var rows: int = view.size[1]
	var area := Rect2(6, HEADER_HEIGHT + 2, size.x - 12, size.y - HEADER_HEIGHT - 8)
	var cell := minf(area.size.x / columns, area.size.y / rows)
	var origin := area.position + (area.size - Vector2(columns, rows) * cell) / 2
	var gap := maxf(1.0, cell * 0.06)
	for y in rows:
		for x in columns:
			draw_rect(Rect2(origin + Vector2(x, y) * cell + Vector2(gap, gap) / 2, Vector2(cell - gap, cell - gap)), FLOOR)
	for hazard in view.hazards:
		_fill_cell(origin, cell, gap, hazard, HAZARD)
	_fill_cell(origin, cell, gap, view.goal, GOAL)
	for agent in view.agents:
		draw_circle(origin + (Vector2(agent[0], agent[1]) + Vector2(0.5, 0.5)) * cell, cell * 0.3, AGENT, true, -1.0, true)

	if _flash > 0.0:
		var board := Rect2(origin, Vector2(columns, rows) * cell).grow(2)
		draw_rect(board, Color(_flash_color, _flash), false, 2.0)
	if stale:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		_draw_centered(font, "no signal")


func _fill_cell(origin: Vector2, cell: float, gap: float, at: Array, color: Color) -> void:
	draw_rect(Rect2(origin + Vector2(at[0], at[1]) * cell + Vector2(gap, gap) / 2, Vector2(cell - gap, cell - gap)), color)


func _draw_centered(font: Font, text: String) -> void:
	draw_string(font, Vector2(0, size.y / 2 + 4), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, MUTED)
