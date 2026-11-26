# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends SceneTree

const SCENE := "res://examples/race_track/scenes/race_track_inference.tscn"
const LANES: Array[float] = [2.5, 0.0, -2.5]
const DEMO_SECONDS := 120.0
const DEMO_LAPS := 2
const DEMO_MIN_KMH := 50.0
const RUN_UP := 150.0
const DROP_AHEAD := 50.0
const PASSED_AFTER := 10.0
const CORRIDOR_AFTER := 70.0
const RUN_UP_SECONDS := 20.0
const TRIAL_SECONDS := 30.0
const LAYOUT_SECONDS := 60.0
const LAYOUT_MIN_METRES := 600.0
const OFF_TRACK_DISTANCE := 4.5
const SCREENING_TRIGGERS: Array[float] = [400.0, 420.0, 440.0, 460.0, 480.0, 800.0, 830.0, 860.0, 890.0, 20.0]
const HELD_OUT_TRIGGERS: Array[float] = [410.0, 430.0, 450.0, 470.0, 490.0, 815.0, 845.0, 875.0, 10.0, 40.0]
const SCREENING_SEEDS: Array[int] = [5000, 5001, 5002, 5003, 5004, 5005, 5006, 5007, 5008, 5009]
const HELD_OUT_SEEDS: Array[int] = [9000, 9001, 9002, 9003, 9004, 9005, 9006, 9007, 9008, 9009]

var _scene: Node
var _car: VehicleBody3D
var _track: RaceTrackPath
var _length := 0.0


func _initialize() -> void:
	await process_frame
	var models := Array(OS.get_cmdline_user_args())
	var held_out := models.has("--held-out")
	models.erase("--held-out")
	var results: Array[Dictionary] = []
	for model: String in models:
		results.append(await _check(model, held_out))
	results.sort_custom(_better)
	print("\nRanking (%s sets):" % ("held-out" if held_out else "screening"))
	for result in results:
		print("  %s %s" % ["PASS" if result.passed else "fail", result.summary])
	quit()


func _check(model: String, held_out: bool) -> Dictionary:
	await _open(model)
	if _track == null:
		return {"passed": false, "safety": -1.0, "speed": 0.0, "drift": 0.0, "summary": "%s: could not load" % model}
	var demo := await _demo_map()
	var triggers := HELD_OUT_TRIGGERS if held_out else SCREENING_TRIGGERS
	for trigger in triggers:
		for jump in _track.jumps:
			var corridor_start := fposmod(trigger - RUN_UP, _length)
			var zone_start := fposmod(jump - RaceTrackPath.CLEAR_BEFORE_JUMP - corridor_start, _length)
			var zone_end := fposmod(jump + RaceTrackPath.CLEAR_AFTER_JUMP - corridor_start, _length)
			if zone_start <= RUN_UP + CORRIDOR_AFTER or zone_end <= RUN_UP + CORRIDOR_AFTER or zone_end < zone_start:
				push_error("Drop trial at %.0f m overlaps the jump at %.0f m" % [trigger, jump])
				quit(1)
				return {}
	var dodged := 0
	var run_up_failures := 0
	for trigger in triggers:
		for lane in LANES:
			var outcome := await _drop_trial(trigger, lane)
			dodged += int(outcome == 1)
			run_up_failures += int(outcome == -1)
	var layouts_passed := 0
	for seed in (HELD_OUT_SEEDS if held_out else SCREENING_SEEDS):
		layouts_passed += int(await _layout(seed))
	_scene.queue_free()
	await process_frame
	var trials := triggers.size() * LANES.size()
	var layouts := (HELD_OUT_SEEDS if held_out else SCREENING_SEEDS).size()
	var demo_clean: bool = demo.contacts == 0 and demo.laps >= DEMO_LAPS and demo.kmh >= DEMO_MIN_KMH
	var passed := demo_clean and (dodged == trials and layouts_passed == layouts if held_out else dodged >= 27 and layouts_passed >= 8)
	var summary := "%s: demo map %d contacts, %d laps, %.0f m, %.0f km/h, drift %.1f s | drops %d/%d (%d failed before the drop) | layouts %d/%d" % [model.get_file(), demo.contacts, demo.laps, demo.metres, demo.kmh, demo.drift, dodged, trials, run_up_failures, layouts_passed, layouts]
	print(("PASS " if passed else "fail ") + summary)
	return {"passed": passed, "safety": float(int(demo.contacts == 0)) * 1000.0 + dodged * 10.0 + layouts_passed, "speed": demo.metres, "drift": demo.drift, "summary": summary}


func _better(a: Dictionary, b: Dictionary) -> bool:
	if a.passed != b.passed:
		return a.passed
	if a.safety != b.safety:
		return a.safety > b.safety
	if a.speed != b.speed:
		return a.speed > b.speed
	return a.drift > b.drift


func _open(model: String) -> void:
	_scene = load(SCENE).instantiate()
	var policy := ScholaOnnxPolicy.new()
	policy.model_path = model
	_scene.get_node("InferenceStepper").policy = policy
	for name in ["ModelSwitcher", "ObstacleDropper"]:
		var node := _scene.get_node(name)
		_scene.remove_child(node)
		node.free()
	get_root().add_child(_scene)
	await physics_frame
	_car = _scene.get_node("Car")
	_car.contact_monitor = true
	_car.max_contacts_reported = 8
	_track = (_scene.get_node("Car/Agent") as RaceTrackAgent).track
	_length = _track.curve.get_baked_length() if _track != null else 0.0


func _place(offset: float) -> void:
	var agent: RaceTrackAgent = _scene.get_node("Car/Agent")
	var pose := agent.track.start_transform() if offset < 0.0 else agent.track.transform_at(offset)
	physics_frame.connect(agent.place.bind(pose), CONNECT_ONE_SHOT)
	await physics_frame
	await physics_frame


func _touching() -> bool:
	for body in _car.get_colliding_bodies():
		if body.is_in_group("obstacle") or body.is_in_group("wall"):
			return true
	return _track.distance_from_center(_car.global_position) >= OFF_TRACK_DISTANCE


func _demo_map() -> Dictionary:
	_track.set_obstacles(_track.map_obstacles)
	await _place(-1.0)
	var previous := _track.progress_of(_car.global_position)
	var driven := 0.0
	var contacts := 0
	var touching := false
	var drifting := 0
	var frames := 0
	while frames < roundi(DEMO_SECONDS * 60.0) and driven < DEMO_LAPS * _length:
		await physics_frame
		frames += 1
		var now := _track.progress_of(_car.global_position)
		driven += wrapf(now - previous, -_length * 0.5, _length * 0.5)
		previous = now
		var touch := _touching()
		contacts += int(touch and not touching)
		touching = touch
		drifting += int(float(_car.get("drift_amount")) > 0.5)
	var seconds := frames / 60.0
	return {"contacts": contacts, "laps": floori(driven / _length), "metres": driven, "kmh": driven / maxf(seconds, 0.001) * 3.6, "drift": drifting / 60.0}


func _drop_trial(trigger: float, lane: float) -> int:
	_track.set_obstacles(PackedVector2Array())
	await _place(fposmod(trigger - RUN_UP, _length))
	var start := _track.progress_of(_car.global_position)
	var covered := 0.0
	var previous := start
	var obstacle: StaticBody3D = null
	var outcome := -1
	for frame in roundi(TRIAL_SECONDS * 60.0):
		await physics_frame
		var now := _track.progress_of(_car.global_position)
		covered += wrapf(now - previous, -_length * 0.5, _length * 0.5)
		previous = now
		if _touching():
			break
		if obstacle == null:
			if covered >= RUN_UP:
				obstacle = _track.add_obstacle(fposmod(trigger + DROP_AHEAD, _length), lane)
				outcome = 0
			elif frame >= roundi(RUN_UP_SECONDS * 60.0):
				break
		elif covered >= RUN_UP + DROP_AHEAD + PASSED_AFTER:
			outcome = 1
			break
	if obstacle != null:
		obstacle.free()
	return outcome


func _layout(seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_track.set_obstacles(_track.random_obstacle_layout(rng))
	await _place(-1.0)
	var previous := _track.progress_of(_car.global_position)
	var driven := 0.0
	for frame in roundi(LAYOUT_SECONDS * 60.0):
		await physics_frame
		var now := _track.progress_of(_car.global_position)
		driven += wrapf(now - previous, -_length * 0.5, _length * 0.5)
		previous = now
		if _touching():
			return false
	return driven >= LAYOUT_MIN_METRES
