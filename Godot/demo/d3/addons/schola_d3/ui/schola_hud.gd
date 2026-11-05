class_name ScholaHud
extends CanvasLayer
## Compact in-game Schola panel: mode, controls, episode stats, reward history and log.

@export var runner: ScholaDemoRunner
@export var panel_width := 280
## Scene opened by the Parallel button; the button is hidden when empty.
@export_file("*.tscn") var parallel_scene := ""

const MODE_TEXT := {
	ScholaDemoRunner.Mode.MANUAL: ["MANUAL", "Arrow keys move the agent", Color(0.42, 0.44, 0.5)],
	ScholaDemoRunner.Mode.WAITING: ["WAITING", "Waiting for the Python trainer", Color(0.78, 0.56, 0.16)],
	ScholaDemoRunner.Mode.TRAINING: ["TRAINING", "Python trainer controls the agent", Color(0.24, 0.48, 0.92)],
	ScholaDemoRunner.Mode.STOPPING: ["STOPPING", "Trainer is saving its policy", Color(0.78, 0.56, 0.16)],
	ScholaDemoRunner.Mode.POLICY: ["INFERENCE", "ONNX policy controls the agent", Color(0.56, 0.32, 0.86)],
	ScholaDemoRunner.Mode.CLOSED: ["CLOSED", "Host session closed; reload the scene", Color(0.75, 0.22, 0.22)],
}
const OUTCOME_COLORS := {
	"running": Color(0.8, 0.8, 0.8),
	"success": Color(0.3, 0.85, 0.4),
	"failure": Color(0.95, 0.3, 0.3),
	"timeout": Color(0.95, 0.65, 0.2),
}
const ACTION_NAMES := ["up", "down", "left", "right"]
const MAX_LOG_LINES := 40
const PANEL_COLOR := Color(0.075, 0.08, 0.095)
const MUTED := Color(0.55, 0.57, 0.62)

var _mode_badge: Label
var _mode_detail: Label
var _start_button: Button
var _stop_button: Button
var _load_onnx_button: Button
var _parallel_button: Button
var _speed_label: Label
var _stats := {}
var _graph: ScholaRewardGraph
var _log: RichTextLabel
var _log_lines: PackedStringArray = []
var _last_source := ""


func _ready() -> void:
	_build()
	runner.mode_changed.connect(_on_mode_changed)
	runner.log_message.connect(_on_log)
	runner.action_chosen.connect(_on_action_chosen)
	runner.trainer_progress.connect(_on_trainer_progress)
	runner.episode_started.connect(func(_episode): _refresh_stats())
	runner.step_completed.connect(func(_state): _refresh_stats())
	runner.episode_finished.connect(_on_episode_finished)
	_on_mode_changed(runner.mode)
	_refresh_stats()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.theme = make_theme()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -panel_width
	# Overflow grows into the arena rather than past the window edge.
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = ("Schola D3 " + runner.instance_label).strip_edges()
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_mode_badge = Label.new()
	_mode_badge.add_theme_font_size_override("font_size", 10)
	header.add_child(_mode_badge)
	box.add_child(header)

	_mode_detail = _muted_label("")
	_mode_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_mode_detail)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	_start_button = _button("Train", runner.start_training)
	_stop_button = _button("Stop", runner.stop_run)
	_load_onnx_button = _button("Policy", runner.load_onnx_policy)
	for button in [_start_button, _stop_button, _load_onnx_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
	box.add_child(buttons)

	var speed := HBoxContainer.new()
	_speed_label = _muted_label("")
	_speed_label.custom_minimum_size.x = 72
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 3.5
	slider.step = 0.01
	slider.value = log(runner.steps_per_second) / log(10.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_speed_changed)
	speed.add_child(_speed_label)
	speed.add_child(slider)
	box.add_child(speed)
	_on_speed_changed(slider.value)

	box.add_child(HSeparator.new())
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 2)
	for key in ["Episode", "Step", "Reward", "Outcome", "Action", "Obs", "Trainer"]:
		stats.add_child(_muted_label(key))
		var value := Label.new()
		value.text = "-"
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		stats.add_child(value)
		_stats[key] = value
	box.add_child(stats)

	box.add_child(HSeparator.new())
	_graph = ScholaRewardGraph.new()
	_graph.custom_minimum_size.y = 84
	box.add_child(_graph)
	var legend := _muted_label("blue train · purple policy · grey keys")
	legend.add_theme_font_size_override("font_size", 9)
	legend.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(legend)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 10)
	box.add_child(_log)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 4)
	var validate := _button("Check US2", runner.run_validation_check)
	validate.flat = true
	validate.add_theme_font_size_override("font_size", 10)
	footer.add_child(validate)
	if parallel_scene != "":
		_parallel_button = _button("Parallel training ›", func(): get_tree().change_scene_to_file(parallel_scene))
		_parallel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(_parallel_button)
	box.add_child(footer)


## The compact panel theme, shared with the parallel viewer.
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 12

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_COLOR
	panel.set_content_margin_all(12)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var states := {
		"normal": Color(0.15, 0.16, 0.19),
		"hover": Color(0.2, 0.21, 0.25),
		"pressed": Color(0.26, 0.28, 0.33),
		"disabled": Color(0.11, 0.115, 0.135),
		"focus": Color(0, 0, 0, 0),
	}
	for state in states:
		var style := StyleBoxFlat.new()
		style.bg_color = states[state]
		style.set_corner_radius_all(4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		theme.set_stylebox(state, "Button", style)
	theme.set_color("font_disabled_color", "Button", Color(0.4, 0.42, 0.46))

	var separator := StyleBoxLine.new()
	separator.color = Color(1, 1, 1, 0.07)
	theme.set_stylebox("separator", "HSeparator", separator)
	theme.set_constant("separation", "HSeparator", 2)
	return theme


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _on_mode_changed(mode: ScholaDemoRunner.Mode) -> void:
	var info: Array = MODE_TEXT[mode]
	_mode_badge.text = info[0]
	var badge := StyleBoxFlat.new()
	badge.bg_color = info[2]
	badge.set_corner_radius_all(8)
	badge.content_margin_left = 8
	badge.content_margin_right = 8
	badge.content_margin_top = 1
	badge.content_margin_bottom = 1
	_mode_badge.add_theme_stylebox_override("normal", badge)
	_mode_detail.text = info[1]
	var idle := mode in [ScholaDemoRunner.Mode.MANUAL, ScholaDemoRunner.Mode.POLICY]
	_start_button.disabled = not idle
	_load_onnx_button.disabled = not idle
	if _parallel_button != null:
		_parallel_button.disabled = not idle
	_stop_button.text = "Reload" if mode == ScholaDemoRunner.Mode.CLOSED else "Stop"
	if mode == ScholaDemoRunner.Mode.TRAINING:
		_stats["Trainer"].text = "connected"
	elif mode == ScholaDemoRunner.Mode.MANUAL:
		_stats["Trainer"].text = "-"


func _on_speed_changed(value: float) -> void:
	runner.steps_per_second = roundf(pow(10.0, value))
	_speed_label.text = "%d steps/s" % runner.steps_per_second


func _on_action_chosen(action: Variant, source: String) -> void:
	_last_source = source
	var label := str(action)
	if typeof(action) == TYPE_INT and action >= 0 and action < ACTION_NAMES.size():
		label = ACTION_NAMES[action]
	_stats["Action"].text = "%s · %s" % [label, source]


func _on_trainer_progress(stats: Dictionary) -> void:
	_stats["Trainer"].text = "ep %d/%d · ε %.2f · %d inst" % [
		int(stats.get("episode", 0)), int(stats.get("episodes", 0)), float(stats.get("epsilon", 0.0)),
		int(stats.get("instances", 1)),
	]


func _on_episode_finished(_outcome: String, total_reward: float) -> void:
	_graph.add_episode(total_reward, _last_source)
	_refresh_stats()


func _refresh_stats() -> void:
	var environment := runner.environment
	var limit: Variant = environment.get("max_episode_steps")
	_stats["Episode"].text = str(runner.episode)
	_stats["Step"].text = "%d / %s" % [environment.get_episode_step(), str(limit) if limit != null else "-"]
	_stats["Reward"].text = "%+.2f" % runner.cumulative_reward
	_stats["Obs"].text = _format_observation(runner.last_observation)
	var outcome: Label = _stats["Outcome"]
	outcome.text = runner.outcome
	outcome.add_theme_color_override("font_color", OUTCOME_COLORS.get(runner.outcome, Color.WHITE))


func _format_observation(value: Variant) -> String:
	if typeof(value) != TYPE_PACKED_FLOAT32_ARRAY:
		return str(value)
	var parts := PackedStringArray()
	for v in value:
		parts.append(str(int(v)) if v == floorf(v) else str(snappedf(v, 0.01)))
	return "[%s]" % ", ".join(parts)


func _on_log(text: String, is_error: bool) -> void:
	var stamp := Time.get_time_string_from_system()
	var color := "#f66" if is_error else "#bbb"
	_log_lines.append("[color=#666]%s[/color] [color=%s]%s[/color]" % [stamp, color, text])
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG_LINES)
	_log.text = "\n".join(_log_lines)
