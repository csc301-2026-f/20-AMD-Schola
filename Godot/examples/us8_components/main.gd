# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Node3D

@onready var host: ScholaTrainingHost = $Host
@onready var agent: ScholaAgent = $Environment/Agent
@onready var body: CharacterBody3D = $Environment/Agent/Body

var telemetry: Label
var mode_button: Button
var running := false
var automatic := false
var observation := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var ray_visuals: Array[MeshInstance3D] = []
var observation_key: String
var action_key: String
var smoke := false
var steps := 0
var saw_hit := false
var travelled := 0.0

func _ready() -> void:
	smoke = "--us8-smoke" in OS.get_cmdline_user_args()
	automatic = smoke
	$Camera.look_at(Vector3.ZERO)
	_build_world()
	_build_hud()
	for index in 3:
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.045, 0.045, 1)
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		visual.material_override = material
		body.add_child(visual)
		ray_visuals.append(visual)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not _accept(host.initialize_session()) or not _accept(host.set_autoreset_mode(2)) or not _accept(host.define()):
		return
	observation_key = agent.observation_space.spaces.keys()[0]
	action_key = agent.action_space.spaces.keys()[0]
	running = _accept(host.reset({}))

func _build_world() -> void:
	_box(Vector3(0, -0.2, 0), Vector3(18, 0.4, 18), Color("17263d"))
	for position in [Vector3(0, 0.5, -4), Vector3(-4, 0.5, 0), Vector3(4, 0.5, -1)]:
		_box(position, Vector3(2, 1, 2), Color("ed9b45"))
	for position in [Vector3(0, 0.5, -9), Vector3(0, 0.5, 9)]:
		_box(position, Vector3(18, 1, 0.4), Color("46617f"))
	for position in [Vector3(-9, 0.5, 0), Vector3(9, 0.5, 0)]:
		_box(position, Vector3(0.4, 1, 18), Color("46617f"))

func _box(position_value: Vector3, size_value: Vector3, color: Color) -> void:
	var obstacle := StaticBody3D.new()
	obstacle.position = position_value
	var mesh := BoxMesh.new()
	mesh.size = size_value
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	obstacle.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = size_value
	var collision := CollisionShape3D.new()
	collision.shape = shape
	obstacle.add_child(collision)
	add_child(obstacle)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	canvas.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "US8  /  REUSABLE SENSORS + ACTUATORS"
	title.add_theme_font_size_override("font_size", 22)
	layout.add_child(title)
	var help := Label.new()
	help.text = "WASD / arrows: move    R: reset    Space: toggle auto\nGreen body · orange obstacles · cyan rays (red on hit)\nKeyboard / scripted controller → native Schola host → GDScript components"
	layout.add_child(help)
	mode_button = Button.new()
	mode_button.focus_mode = Control.FOCUS_NONE
	mode_button.text = "Toggle automatic controller (no trained model)"
	mode_button.pressed.connect(func() -> void: automatic = not automatic)
	layout.add_child(mode_button)
	var reset_button := Button.new()
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.text = "Reset position"
	reset_button.pressed.connect(_reset)
	layout.add_child(reset_button)
	telemetry = Label.new()
	layout.add_child(telemetry)

func _accept(result: Dictionary) -> bool:
	if result.status.code == 0:
		return true
	running = false
	telemetry.text = "Schola error: " + str(result.status.message)
	push_error(telemetry.text)
	if smoke:
		get_tree().quit(1)
	return false

func _reset() -> void:
	if running:
		running = _accept(host.reset({}))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			automatic = not automatic
		elif event.keycode == KEY_R:
			_reset()

func _physics_process(_delta: float) -> void:
	if not running:
		return
	var direction := Vector3.ZERO
	if automatic:
		direction = Vector3(1, 0, 0) if observation[0] > 0 and observation[1] < 0.35 else Vector3(0, 0, -1)
		if body.position.x > 7 or body.position.z < -7:
			_reset()
	else:
		direction.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		direction.z = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	direction = direction.normalized() * float($Environment/Agent/Movement.maximum_speed)
	var result := host.step({"actions": [{"player": {action_key: PackedFloat32Array([direction.x, 0, direction.z])}}]})
	if not _accept(result):
		return
	observation = result.value.state[0].player.observation[observation_key]
	var previous := body.position
	body.move_and_slide() # The actuator sets velocity; this scene owns physics.
	travelled += previous.distance_to(body.position)
	steps += 1
	_draw_rays()
	telemetry.text = "Mode: %s   Native steps: %d\nAction: %s\nFront / left / right [hit, distance / 6m]:\n%s\nEdit RaySensor and Movement scripts to customize behavior." % ["AUTO" if automatic else "KEYBOARD", steps, direction, observation]
	if smoke and steps == 90:
		if travelled > 1.0 and saw_hit and observation.size() == 6:
			print("US8_SMOKE_OK: native composition, movement, and ray hits verified")
			get_tree().quit(0)
		else:
			push_error("US8 smoke failed: movement or native ray observation missing")
			get_tree().quit(1)

func _draw_rays() -> void:
	var directions := [Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]
	for index in 3:
		var hit := observation[index * 2] > 0
		saw_hit = saw_hit or hit
		var length := observation[index * 2 + 1] * 6.0 if hit else 6.0
		var visual := ray_visuals[index]
		visual.scale.z = maxf(length, 0.001)
		visual.position = directions[index] * length * 0.5
		visual.rotation.y = PI / 2 if index > 0 else 0.0
		var material := visual.material_override as StandardMaterial3D
		material.albedo_color = Color("ff5c64") if hit else Color("4bd9e8")
		visual.material_override = material
