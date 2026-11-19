# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends SceneTree

const SCENE := "res://examples/race_track/scenes/race_track_inference.tscn"
const MODELS: Array[String] = [
	"res://examples/race_track/policies/race_track.onnx",
	"res://tests/inference/fixtures/schola_ppo_race_car.onnx",
]
const SECONDS := 50
const OFF_TRACK_DISTANCE := 10.0


func _initialize() -> void:
	await process_frame
	var models: Array = Array(OS.get_cmdline_user_args())
	if models.is_empty():
		models = MODELS
	for model in models:
		print(await evaluate(model))
	quit()


func evaluate(model: String) -> String:
	var scene: Node = load(SCENE).instantiate()
	var stepper: ScholaInferenceStepper = scene.get_node("InferenceStepper")
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = model
	stepper.policy = policy
	var failures: Array[String] = []
	stepper.inference_failed.connect(func(message: String) -> void: failures.append(message))
	get_root().add_child(scene)
	var car: VehicleBody3D = scene.get_node("Car")
	var track: RaceTrackPath = scene.get_node("Car/Agent").track
	var length := track.curve.get_baked_length()
	var previous := track.progress_of(car.global_position)
	var driven := 0.0
	var frames := SECONDS * Engine.physics_ticks_per_second
	var frame := 0
	while frame < frames and failures.is_empty() and track.distance_from_center(car.global_position) < OFF_TRACK_DISTANCE:
		await physics_frame
		var now := track.progress_of(car.global_position)
		driven += wrapf(now - previous, -length * 0.5, length * 0.5)
		previous = now
		frame += 1
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		return "%s: could not run: %s" % [model, failures[0]]
	var ending := "stayed on the track" if frame == frames else "left the track"
	return "%s: %.1f m along the track (%.2f laps) in %.1f s, %s" % [model, driven, driven / length, frame / float(Engine.physics_ticks_per_second), ending]
