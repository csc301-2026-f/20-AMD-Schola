# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Node3D

@onready var host: ScholaTrainingHost = $TrainingHost
@onready var agent: RaceTrackAgent = $RaceTrackEnvironment/Car/Agent
@onready var car: VehicleBody3D = $RaceTrackEnvironment/Car
var telemetry: Label
var running := false
var smoke := false
var steps := 0
var saw_velocity := false
var action_key: String

func _ready() -> void:
	smoke = "--race-track-smoke" in OS.get_cmdline_user_args()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	canvas.add_child(panel)
	telemetry = Label.new()
	panel.add_child(telemetry)
	await get_tree().physics_frame
	if not _accept(host.initialize_session()) or not _accept(host.set_autoreset_mode(2)) or not _accept(host.define()):
		return
	action_key = agent.action_space.spaces.keys()[0]
	running = _accept(host.reset({}))

func _accept(result: Dictionary) -> bool:
	if result.status.code == 0:
		return true
	running = false
	telemetry.text = "Schola error: " + str(result.status.message)
	push_error(telemetry.text)
	if smoke:
		get_tree().quit(1)
	return false

func _physics_process(_delta: float) -> void:
	if not running:
		return
	if Input.is_physical_key_pressed(KEY_R):
		running = _accept(host.reset({}))
		return
	var steering := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var pedal := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	if smoke:
		pedal = 0.01
		steering = 0.005 if steps > 30 else 0.0
	var result := host.step({"actions": [{agent.get_resolved_agent_id(): {action_key: PackedFloat32Array([steering, pedal])}}]})
	if not _accept(result):
		return
	var state: Dictionary = result.value.state[0][agent.get_resolved_agent_id()]
	var observation: Dictionary = state.observation
	var keys: Array = agent.observation_space.spaces.keys()
	var velocity: PackedFloat32Array = observation[keys[1]]
	saw_velocity = saw_velocity or Vector3(velocity[0], velocity[1], velocity[2]).length() > 0.1
	steps += 1
	telemetry.text = "RACE TRACK / COMPOSED SENSORS + ACTUATOR\nW: throttle  S: brake  A/D: steer  R: reset\nKeyboard controller (no trained policy) → native host → components\nSteps: %d   Speed: %.1f m/s\nTrack [offset / 5m, direction]: %s\nVelocity [forward, right, up] / 2m/s: %s\nControls [steering, pedal]: %s\nReward: %.3f" % [steps, car.linear_velocity.length(), observation[keys[0]], velocity, Vector2(steering, pedal), state.reward]
	if smoke and (state.terminated or state.truncated):
		push_error("Keyboard demo unexpectedly ended the episode")
		get_tree().quit(1)
		return
	if state.terminated or state.truncated:
		running = _accept(host.reset({}))
	if smoke and steps == 120:
		if observation.size() != 2 or observation[keys[0]].size() != 6 or velocity.size() != 3 or not saw_velocity:
			push_error("Race track smoke: missing composed observations or vehicle motion")
			get_tree().quit(1)
			return
		if not _accept(host.reset({})):
			return
		if car.linear_velocity != Vector3.ZERO or car.engine_force != 0.0 or car.steering != 0.0 or car.brake != 0.0:
			push_error("Race track smoke: reset did not clear physics and controls")
			get_tree().quit(1)
			return
		print("RACE_TRACK_SMOKE_OK: native sensor composition, vehicle motion and reset verified")
		get_tree().quit(0)
