class_name ScholaParallelViewer
extends Control
## One window for parallel training: starts python/train_parallel.py with the chosen number of
## headless Godot instances and draws every instance's board from the reports they send over UDP.
## The instances stay separate processes, so they still simulate in parallel.

enum State { IDLE, STARTING, TRAINING, STOPPING, DONE, FAILED }

const STATE_TEXT := {
	State.IDLE: ["IDLE", "Choose the instance count and press Start", Color(0.42, 0.44, 0.5)],
	State.STARTING: ["STARTING", "Launching Godot instances and the trainer", Color(0.78, 0.56, 0.16)],
	State.TRAINING: ["TRAINING", "Instances train one shared policy", Color(0.24, 0.48, 0.92)],
	State.STOPPING: ["STOPPING", "Trainer is saving its policy", Color(0.78, 0.56, 0.16)],
	State.DONE: ["DONE", "Policy saved; open the main scene to run it", Color(0.22, 0.6, 0.36)],
	State.FAILED: ["FAILED", "See python/logs/parallel.log", Color(0.75, 0.22, 0.22)],
}
## The + button stops at the larger of this and the CPU's logical core count.
const MIN_INSTANCE_CAP := 16
const EPISODE_CHOICES := [400, 800, 1200, 2000, 4000, 8000]
const SPEED_CHOICES := [20, 60, 200, 1000, 2000]
const STALE_SEC := 3.0
const STOP_GRACE_SEC := 15.0
const MAX_LOG_LINES := 30

@export var python_executable := "python"
@export_file("*.py") var launcher_script := "res://python/train_parallel.py"
@export_file("*.tscn") var main_scene := "res://demo/main.tscn"
@export var viewer_port := 9100
@export var base_port := 8000
@export var panel_width := 280

var instances := 4
var episodes := 1200
var speed := 200
var state := State.IDLE

var _udp: PacketPeerUDP
var _pid := -1
var _boards := {}
var _senders := {}
var _last_seen := {}
var _steps := {}
var _stop_deadline := 0.0
var _rate_steps := 0
var _rate_time := 0.0
var _successes := 0
var _finished := 0

var _grid: GridContainer
var _badge: Label
var _detail: Label
var _count_label: Label
var _episodes_label: Label
var _speed_label: Label
var _setting_buttons: Array[Button] = []
var _start_button: Button
var _stop_button: Button
var _back_button: Button
var _stats := {}
var _graph: ScholaRewardGraph
var _log: RichTextLabel
var _log_lines: PackedStringArray = []


func _ready() -> void:
	instances = clampi(mini(instances, OS.get_processor_count()), 1, max_instances())
	_build()
	_udp = PacketPeerUDP.new()
	var error := _udp.bind(viewer_port, "127.0.0.1")
	if error != OK:
		_udp = null
		_log_line("could not listen for instance reports on UDP %d (%s)" % [viewer_port, error_string(error)], true)
	_rebuild_boards()
	_set_state(State.IDLE)


func _exit_tree() -> void:
	if _is_running():
		_send_stop()


func _process(delta: float) -> void:
	_receive_reports()
	var now := Time.get_ticks_msec() / 1000.0
	for board_port in _boards:
		_boards[board_port].stale = state == State.TRAINING and now - _last_seen.get(board_port, now) > STALE_SEC

	_rate_time += delta
	if _rate_time >= 0.5:
		_stats["Steps/s"].text = "%d" % roundi(_rate_steps / _rate_time) if state == State.TRAINING else "-"
		_rate_steps = 0
		_rate_time = 0.0

	if _pid != -1 and not OS.is_process_running(_pid):
		var code := OS.get_process_exit_code(_pid)
		_pid = -1
		if code == 0:
			_log_line("training finished; policy saved to policies/q_policy.onnx")
			_set_state(State.DONE)
		else:
			_log_line("launcher exited with code %d; see python/logs/parallel.log" % code, true)
			_set_state(State.FAILED)
	elif state == State.STOPPING and now > _stop_deadline and _pid != -1:
		_log_line("trainer did not stop in time; ending it", true)
		OS.kill(_pid)


func start() -> void:
	if _is_running():
		return
	_rebuild_boards()
	_successes = 0
	_finished = 0
	_graph.clear()
	_stats["Episodes"].text = "0 / %d" % episodes
	_stats["Success"].text = "-"
	var args := PackedStringArray([
		ProjectSettings.globalize_path(launcher_script),
		"--godot", OS.get_executable_path(),
		"--instances", str(instances),
		"--base-port", str(base_port),
		"--episodes", str(episodes),
		"--speed", str(speed),
		"--viewer-port", str(viewer_port),
		"--log-file", ProjectSettings.globalize_path("res://python/logs/parallel.log"),
	])
	_pid = OS.create_process(python_executable, args)
	if _pid == -1:
		_log_line("could not run '%s'; set python_executable on the viewer" % python_executable, true)
		_set_state(State.FAILED)
		return
	_log_line("started %d instance(s) on ports %d-%d, %d episodes at %d steps/s each" % [instances, base_port, base_port + instances - 1, episodes, speed])
	_set_state(State.STARTING)


func stop() -> void:
	if state != State.STARTING and state != State.TRAINING:
		return
	if _senders.is_empty():
		OS.kill(_pid)
		_log_line("stopped before any instance reported")
		return
	_send_stop()
	_stop_deadline = Time.get_ticks_msec() / 1000.0 + STOP_GRACE_SEC
	_log_line("asked the trainer to save and stop")
	_set_state(State.STOPPING)


func _send_stop() -> void:
	if _udp == null:
		return
	for sender in _senders.values():
		_udp.set_dest_address(sender[0], sender[1])
		_udp.put_packet("stop".to_utf8_buffer())


func _receive_reports() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var report: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(report) != TYPE_DICTIONARY or not report.has("port"):
			continue
		var board_port := int(report.port)
		if not _boards.has(board_port):
			continue
		_senders[board_port] = [_udp.get_packet_ip(), _udp.get_packet_port()]
		_last_seen[board_port] = Time.get_ticks_msec() / 1000.0
		_boards[board_port].set_report(report)
		var steps := int(report.get("steps", 0))
		_rate_steps += maxi(0, steps - _steps.get(board_port, 0))
		_steps[board_port] = steps
		for finished in report.get("finished", []):
			_finished += 1
			if finished[1] == "success":
				_successes += 1
			_graph.add_episode(finished[0], "Python trainer")
		if _finished > 0:
			_stats["Success"].text = "%d%%" % roundi(100.0 * _successes / _finished)
		var progress: Dictionary = report.get("progress", {})
		if not progress.is_empty():
			_stats["Episodes"].text = "%d / %d" % [int(progress.episode), int(progress.episodes)]
			_stats["Epsilon"].text = "%.2f" % float(progress.epsilon)
		if state == State.STARTING and report.get("mode") == "TRAINING":
			_set_state(State.TRAINING)
		_stats["Live"].text = "%d / %d" % [_senders.size(), instances]


func _rebuild_boards() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_boards.clear()
	_senders.clear()
	_last_seen.clear()
	_steps.clear()
	_grid.columns = ceili(sqrt(instances))
	for index in instances:
		var board := ScholaMiniBoard.new()
		board.port = base_port + index
		board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid.add_child(board)
		_boards[board.port] = board
	_stats["Live"].text = "0 / %d" % instances


func _change_instances(delta: int) -> void:
	instances = clampi(instances + delta, 1, max_instances())
	_count_label.text = str(instances)
	_rebuild_boards()


func _change_choice(choices: Array, current: int, delta: int) -> int:
	var index := choices.find(current)
	return choices[clampi(index + delta, 0, choices.size() - 1)]


func _change_episodes(delta: int) -> void:
	episodes = _change_choice(EPISODE_CHOICES, episodes, delta)
	_episodes_label.text = str(episodes)


func _change_speed(delta: int) -> void:
	speed = _change_choice(SPEED_CHOICES, speed, delta)
	_speed_label.text = str(speed)


static func max_instances() -> int:
	return maxi(MIN_INSTANCE_CAP, OS.get_processor_count())


func _is_running() -> bool:
	return state in [State.STARTING, State.TRAINING, State.STOPPING]


func _set_state(new_state: State) -> void:
	state = new_state
	var info: Array = STATE_TEXT[state]
	_badge.text = info[0]
	var badge := StyleBoxFlat.new()
	badge.bg_color = info[2]
	badge.set_corner_radius_all(8)
	badge.content_margin_left = 8
	badge.content_margin_right = 8
	badge.content_margin_top = 1
	badge.content_margin_bottom = 1
	_badge.add_theme_stylebox_override("normal", badge)
	_detail.text = info[1]
	var running := _is_running()
	for board in _boards.values():
		board.placeholder = "starting…" if running else "idle"
	for button in _setting_buttons:
		button.disabled = running
	_start_button.disabled = running
	_stop_button.disabled = state != State.STARTING and state != State.TRAINING
	_back_button.disabled = running


# --- Layout -----------------------------------------------------------------------------------


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.11, 0.115, 0.135)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var boards := MarginContainer.new()
	boards.anchor_right = 1.0
	boards.anchor_bottom = 1.0
	boards.offset_right = -panel_width
	for side in ["left", "right", "top", "bottom"]:
		boards.add_theme_constant_override("margin_" + side, 10)
	add_child(boards)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	boards.add_child(_grid)

	var panel := PanelContainer.new()
	panel.theme = ScholaHud.make_theme()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -panel_width
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Parallel training"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 10)
	header.add_child(_badge)
	box.add_child(header)
	_detail = _muted("")
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)

	_count_label = _stepper(box, "Instances", str(instances), _change_instances)
	_episodes_label = _stepper(box, "Episodes", str(episodes), _change_episodes)
	_speed_label = _stepper(box, "Steps/s each", str(speed), _change_speed)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	_start_button = _button("Start", start)
	_stop_button = _button("Stop", stop)
	_back_button = _button("Back", func(): get_tree().change_scene_to_file(main_scene))
	for button in [_start_button, _stop_button, _back_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
	box.add_child(buttons)

	box.add_child(HSeparator.new())
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 2)
	for key in ["Live", "Episodes", "Epsilon", "Success", "Steps/s"]:
		stats.add_child(_muted(key))
		var value := Label.new()
		value.text = "-"
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(value)
		_stats[key] = value
	box.add_child(stats)

	box.add_child(HSeparator.new())
	_graph = ScholaRewardGraph.new()
	_graph.max_episodes = 200
	_graph.custom_minimum_size.y = 84
	box.add_child(_graph)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 10)
	box.add_child(_log)


func _stepper(parent: Control, label: String, value: String, change: Callable) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_label := _muted(label)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var minus := _button("−", change.bind(-1))
	var value_label := Label.new()
	value_label.text = value
	value_label.custom_minimum_size.x = 44
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := _button("+", change.bind(1))
	for control in [minus, value_label, plus]:
		row.add_child(control)
	_setting_buttons.append_array([minus, plus])
	parent.add_child(row)
	return value_label


func _muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", ScholaHud.MUTED)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _log_line(text: String, is_error := false) -> void:
	var stamp := Time.get_time_string_from_system()
	var color := "#f66" if is_error else "#bbb"
	_log_lines.append("[color=#666]%s[/color] [color=%s]%s[/color]" % [stamp, color, text])
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG_LINES)
	_log.text = "\n".join(_log_lines)
	print("Schola D3 viewer: " + text)
