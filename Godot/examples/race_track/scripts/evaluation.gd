# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackEvaluation
extends RefCounted

## Drives the inference scene without Python and measures how far the car gets.

const SCENE := "res://examples/race_track/scenes/race_track_inference.tscn"
## Pass instead of a model path to drive with seeded uniform random actions.
const RANDOM := "random"
const OFF_TRACK_DISTANCE := RaceTrackEnvironment.DEFAULT_MAXIMUM_TRACK_DISTANCE


## Drives one episode under `parent` for at most `seconds` of simulated time, stopping
## early if the car leaves the track or inference fails. `model` is an ONNX path or
## RANDOM. Returns {model, metres, laps, seconds, stayed_on_track, error}.
static func drive(parent: Node, model: String, seconds: float, seed: int = 0) -> Dictionary:
	var scene: Node = load(SCENE).instantiate()
	var stepper: ScholaInferenceStepper = scene.get_node("InferenceStepper")
	var failures: Array[String] = []
	var random: RandomNumberGenerator = null
	if model == RANDOM:
		for node: Node in [stepper, scene.get_node("ModelSwitcher")]:
			scene.remove_child(node)
			node.free()
		random = RandomNumberGenerator.new()
		random.seed = seed
	else:
		var policy := ScholaOnnxPolicy.new()
		policy.model_path = model
		stepper.policy = policy
		stepper.inference_failed.connect(func(message: String) -> void: failures.append(message))
	parent.add_child(scene)
	var tree := parent.get_tree()
	var car: VehicleBody3D = scene.get_node("Car")
	var agent: RaceTrackAgent = scene.get_node("Car/Agent")
	var track := agent.track
	var length := track.curve.get_baked_length()
	var previous := track.progress_of(car.global_position)
	var driven := 0.0
	var frames := roundi(seconds * Engine.physics_ticks_per_second)
	var frame := 0
	while frame < frames and failures.is_empty() and track.distance_from_center(car.global_position) < OFF_TRACK_DISTANCE:
		if random != null:
			agent.controls._act(PackedFloat32Array([random.randf_range(-1.0, 1.0), random.randf_range(-1.0, 1.0)]))
		await tree.physics_frame
		var now := track.progress_of(car.global_position)
		driven += wrapf(now - previous, -length * 0.5, length * 0.5)
		previous = now
		frame += 1
	scene.queue_free()
	await tree.process_frame
	return {
		"model": model,
		"metres": driven,
		"laps": driven / length,
		"seconds": frame / float(Engine.physics_ticks_per_second),
		"stayed_on_track": frame == frames,
		"error": "" if failures.is_empty() else failures[0],
	}


static func describe(result: Dictionary) -> String:
	if not result.error.is_empty():
		return "%s: could not run: %s" % [result.model, result.error]
	var ending := "stayed on the track" if result.stayed_on_track else "left the track"
	return "%s: %.1f m along the track (%.2f laps) in %.1f s, %s" % [result.model, result.metres, result.laps, result.seconds, ending]
