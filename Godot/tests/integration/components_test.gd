# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

class Sensor extends ScholaSensor:
	var value: Variant = 1
	func _observe() -> Variant:
		return value

class CountingSensor extends Sensor:
	var validations: int = 0
	func _get_component_errors() -> PackedStringArray:
		validations += 1
		return PackedStringArray()

class Actuator extends ScholaActuator:
	var calls: int = 0
	var value: Variant
	func _act(action: Variant) -> void:
		calls += 1
		value = action

class DirectAgent extends ScholaAgent:
	var value: Variant
	func _observe() -> Variant:
		return 2
	func _act(action: Variant) -> void:
		value = action

class ComponentEnvironment extends ScholaEnvironment:
	func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
		pass
	func _get_step_result(_agent: ScholaAgent) -> Variant:
		return {"reward": 0}

var driver: RefCounted
var environment: ComponentEnvironment
var agent: ScholaAgent

func before(
	_do_skip := not ClassDB.class_exists("ScholaEnvironmentTestDriver"),
	_skip_reason := "Build with integration_tests=yes to run the component suite."
) -> void:
	pass

func before_test() -> void:
	driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")
	environment = auto_free(ComponentEnvironment.new())
	agent = ScholaAgent.new()
	agent.name = "A"
	environment.add_child(agent)
	add_child(environment)

func after_test() -> void:
	driver = null

func _space() -> ScholaDiscreteSpace:
	var result := ScholaDiscreteSpace.new()
	result.n = 3
	return result

func _sensor(id: String, parent: Node = null) -> Sensor:
	var sensor := Sensor.new()
	sensor.component_id = id
	sensor.space = _space()
	if parent == null:
		parent = agent
	parent.add_child(sensor)
	return sensor

func _actuator(id: String) -> Actuator:
	var actuator := Actuator.new()
	actuator.component_id = id
	actuator.space = _space()
	agent.add_child(actuator)
	return actuator

func test_composition_preserves_tree_order_through_native_adapter() -> void:
	_sensor("z")
	var branch := Node.new()
	agent.add_child(branch)
	_sensor("a", branch)
	var z := _actuator("z")
	var a := _actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var response: Dictionary = driver.call("step", environment, {"A": {"00000000:z": 2, "00000001:a": 1}})
	assert_bool(response.ok).is_true()
	assert_array(response.states.A.observation.keys()).contains_exactly(["00000000:z", "00000001:a"])
	assert_int(z.value).is_equal(2)
	assert_int(a.value).is_equal(1)

func test_invalid_action_has_no_component_side_effects() -> void:
	_sensor("s")
	var first := _actuator("first")
	var second := _actuator("second")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	assert_bool(driver.call("step", environment, {"A": {"00000000:first": 1, "00000001:second": 99}}).ok).is_false()
	assert_int(first.calls).is_equal(0)
	assert_int(second.calls).is_equal(0)

func test_component_observations_are_stacked_and_reset_between_episodes() -> void:
	var sensor := _sensor("s")
	_actuator("a")
	var stacker := ScholaStacker.new()
	stacker.output_kind = 1 # Dict history accepts the composed observation Dict.
	stacker.stack_size = 2
	stacker.default_point = {"00000000:s": 0}
	agent.observation_adapters = [stacker]
	assert_bool(driver.call("initialize", environment).ok).is_true()
	var initial: Dictionary = driver.call("reset", environment)
	assert_bool(initial.ok).is_true()
	assert_dict(initial.states.A.observation).is_equal({
		"00000000:s_0": 1, "00000000:s_1": 0,
	})
	sensor.value = 2
	var response: Dictionary = driver.call("step", environment, {"A": {"00000000:a": 1}})
	assert_bool(response.ok).is_true()
	assert_dict(response.states.A.observation).is_equal({
		"00000000:s_0": 2, "00000000:s_1": 1,
	})
	var reset: Dictionary = driver.call("reset", environment)
	assert_bool(reset.ok).is_true()
	assert_dict(reset.states.A.observation).is_equal({
		"00000000:s_0": 2, "00000000:s_1": 0,
	})

func test_movement_rejects_an_incompatible_space_before_dispatch() -> void:
	_sensor("s")
	var body := CharacterBody3D.new()
	body.name = "Body"
	agent.add_child(body)
	var movement: ScholaActuator = load("res://addons/schola/components/movement_actuator_3d.gd").new()
	agent.add_child(movement)
	movement.body_path = NodePath("../Body")
	movement.component_id = "move"
	movement.space = _space() # A valid space, but its scalar actions cannot set XYZ velocity.
	assert_bool(movement.get_configuration_errors().is_empty()).is_false()
	assert_bool(driver.call("initialize", environment).ok).is_false()
	movement.maximum_speed = 1.0 # Regenerate the declared space.
	movement.space.shape = PackedInt32Array([1])
	assert_bool(driver.call("initialize", environment).ok).is_false()
	movement.maximum_speed = 1.0
	movement.space.high = PackedFloat32Array([10])
	assert_bool(driver.call("initialize", environment).ok).is_false()
	movement.maximum_speed = 1.0
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	movement.space.shape = PackedInt32Array([1])
	assert_bool(driver.call("step", environment, {"A": {"00000000:move": PackedFloat32Array([1, 0, 0])}}).ok).is_false()
	assert_vector(body.velocity).is_equal(Vector3.ZERO)

func test_duplicate_identifiers_rejected() -> void:
	_sensor("same")
	_sensor("same")
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_false()

func test_changed_layout_requires_redefinition() -> void:
	_sensor("s")
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	_sensor("new")
	assert_bool(driver.call("step", environment, {"A": {"00000000:a": 1}}).ok).is_false()

func test_ray_sensor_and_movement_actuator_scripts_load() -> void:
	var ray_sensor: ScholaSensor = auto_free(load("res://addons/schola/components/ray_cast_sensor_3d.gd").new())
	var movement: ScholaActuator = auto_free(load("res://addons/schola/components/movement_actuator_3d.gd").new())
	assert_bool(ray_sensor.space is ScholaBoxSpace).is_true()
	assert_str(movement.space.get_definition_error()).is_empty()

func test_movement_applies_local_velocity_and_rejects_missing_body() -> void:
	_sensor("s")
	var movement: ScholaActuator = load("res://addons/schola/components/movement_actuator_3d.gd").new()
	movement.component_id = "move"
	agent.add_child(movement)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	var body := CharacterBody3D.new()
	body.name = "Body"
	body.rotation.y = PI / 2.0
	agent.add_child(body)
	movement.body_path = NodePath("../Body")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	assert_bool(driver.call("step", environment, {"A": {"00000000:move": PackedFloat32Array([1, 0, 0])}}).ok).is_true()
	assert_vector(body.velocity).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.0001)

func test_ray_reports_hit_distance_and_miss() -> void:
	var sensor: ScholaSensor = load("res://addons/schola/components/ray_cast_sensor_3d.gd").new()
	sensor.component_id = "ray"
	agent.add_child(sensor)
	var ray := RayCast3D.new()
	ray.name = "Ray"
	ray.target_position = Vector3(0, 0, -10)
	agent.add_child(ray)
	var paths: Array[NodePath] = [NodePath("../Ray")]
	sensor.rays = paths
	_actuator("a")
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	obstacle.add_child(collision)
	obstacle.position = Vector3(0, 0, -5)
	agent.add_child(obstacle)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var hit: Dictionary = driver.call("step", environment, {"A": {"00000000:a": 0}})
	assert_bool(hit.ok).is_true()
	var values: PackedFloat32Array = hit.states.A.observation["00000000:ray"]
	assert_float(values[0]).is_equal(1.0)
	assert_float(values[1]).is_equal_approx(0.45, 0.001)
	obstacle.position.x = 20
	await get_tree().physics_frame
	await get_tree().physics_frame
	var miss: Dictionary = driver.call("step", environment, {"A": {"00000000:a": 0}})
	assert_bool(miss.ok).is_true()
	assert_array(Array(miss.states.A.observation["00000000:ray"])).contains_exactly([0.0, 0.0])

func test_direct_hooks_take_precedence_over_components() -> void:
	environment.remove_child(agent)
	agent.free()
	var direct := DirectAgent.new()
	agent = direct
	agent.name = "A"
	agent.observation_space = _space()
	agent.action_space = _space()
	environment.add_child(agent)
	_sensor("ignored").space = null
	_actuator("ignored").space = null
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var result: Dictionary = driver.call("step", environment, {"A": 1})
	assert_bool(result.ok).is_true()
	assert_int(result.states.A.observation).is_equal(2)
	assert_int(direct.value).is_equal(1)

func test_nested_agent_is_a_discovery_boundary() -> void:
	_sensor("outer")
	_actuator("outer")
	var nested := ScholaAgent.new()
	agent.add_child(nested)
	_sensor("inner", nested)
	assert_array(agent.get_effective_observation_space().spaces.keys()).contains_exactly(["00000000:outer"])

func test_configuration_errors_cover_placement_space_and_duplicates() -> void:
	var orphan: ScholaSensor = auto_free(ScholaSensor.new())
	assert_bool(orphan.get_configuration_errors().is_empty()).is_false()
	var first := _sensor("duplicate")
	var second := _sensor("duplicate")
	assert_bool(first.get_configuration_errors().is_empty()).is_false()
	second.component_id = "unique"
	assert_bool(first.get_configuration_errors().is_empty()).is_true()
	first.space = null
	assert_bool(first.get_configuration_errors().is_empty()).is_false()

func test_dispatch_validation_work_scales_with_component_count() -> void:
	var sensors: Array[CountingSensor] = []
	for index in 12:
		var sensor := CountingSensor.new()
		sensor.component_id = "sensor" + str(index)
		sensor.space = _space()
		agent.add_child(sensor)
		sensors.append(sensor)
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	for sensor in sensors:
		sensor.validations = 0
	assert_bool(driver.call("step", environment, {"A": {"00000000:a": 0}}).ok).is_true()
	# Validation must be bounded per component, independent of sibling count.
	for sensor in sensors:
		assert_int(sensor.validations).is_less_equal(8)

func test_unicode_ids_round_trip_through_observation_and_action_dispatch() -> void:
	_sensor("café猫🌍")
	var actuator := _actuator("café猫🌍")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var response: Dictionary = driver.call("step", environment, {"A": {"00000000:café猫🌍": 2}})
	assert_bool(response.ok).is_true()
	assert_dict(response.states.A.observation).is_equal({"00000000:café猫🌍": 1})
	assert_int(actuator.calls).is_equal(1)
	assert_int(actuator.value).is_equal(2)

func test_in_place_ray_append_is_rejected_until_space_is_synchronized() -> void:
	var sensor: ScholaSensor = load("res://addons/schola/components/ray_cast_sensor_3d.gd").new()
	sensor.component_id = "rays"
	agent.add_child(sensor)
	var ray := RayCast3D.new()
	ray.name = "Ray"
	ray.target_position = Vector3(0, 0, -1)
	agent.add_child(ray)
	sensor.add_ray(NodePath("../Ray"))
	_actuator("a")
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	assert_bool(driver.call("initialize", environment).ok).is_true()
	sensor.rays.append(NodePath("../Ray"))
	assert_bool(sensor.get_configuration_errors().is_empty()).is_false()
	assert_bool(driver.call("reset", environment).ok).is_false()
	# Training environments initialize once; a new session must redefine spaces.
	var replacement: ComponentEnvironment = auto_free(ComponentEnvironment.new())
	environment.remove_child(agent)
	environment = replacement
	environment.add_child(agent)
	add_child(environment)
	assert_bool(driver.call("initialize", environment).ok).is_false()
	# Reassignment intentionally runs the setter after an in-place array edit.
	sensor.rays = sensor.rays
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	assert_array(Array(sensor.space.shape)).contains_exactly([4])
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	sensor.add_ray(NodePath("../Ray"))
	assert_bool(sensor.get_configuration_errors().is_empty()).is_true()
	assert_array(Array(sensor.space.shape)).contains_exactly([6])

func test_composed_spaces_are_not_serialized_into_agent_properties() -> void:
	var original: Node = auto_free(load("res://examples/us8_components/main.tscn").instantiate())
	var composed := original.get_node("Environment/Agent") as ScholaAgent
	assert_that(composed.observation_space).is_null()
	assert_that(composed.action_space).is_null()
	assert_array(composed.get_effective_observation_space().spaces.keys()).contains_exactly(["00000000:rays"])
	assert_array(composed.get_effective_action_space().spaces.keys()).contains_exactly(["00000000:movement"])
	var packed := PackedScene.new()
	assert_int(packed.pack(original)).is_equal(OK)
	var path := "user://us8_composition_round_trip.tscn"
	assert_int(ResourceSaver.save(packed, path)).is_equal(OK)
	var reloaded: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var restored: Node = auto_free(reloaded.instantiate())
	var restored_agent := restored.get_node("Environment/Agent") as ScholaAgent
	assert_that(restored_agent.observation_space).is_null()
	assert_that(restored_agent.action_space).is_null()
	assert_array(restored_agent.get_effective_observation_space().spaces.keys()).contains_exactly(["00000000:rays"])
	restored_agent.get_node("RaySensor").free()
	assert_that(restored_agent.get_effective_observation_space()).is_null()
	assert_int(packed.pack(restored)).is_equal(OK)
	var restored_again: Node = auto_free(packed.instantiate())
	assert_that(restored_again.get_node("Environment/Agent").get_effective_observation_space()).is_null()
	DirAccess.remove_absolute(path)

func test_stored_spaces_remain_separate_from_component_composition() -> void:
	var explicit := _space()
	agent.observation_space = explicit
	var sensor := _sensor("sensor")
	assert_that(agent.observation_space).is_same(explicit)
	assert_bool(agent.get_effective_observation_space() is ScholaDictSpace).is_true()
	sensor.free()
	assert_that(agent.get_effective_observation_space()).is_same(explicit)

func test_components_do_not_subscribe_to_runtime_tree_changes() -> void:
	var before := get_tree().get_signal_connection_list("tree_changed").size()
	for index in 16:
		_sensor("s" + str(index))
		_actuator("a" + str(index))
	assert_int(get_tree().get_signal_connection_list("tree_changed").size()).is_equal(before)

func test_runtime_preflight_runs_once_per_component_per_dispatch() -> void:
	var sensor := CountingSensor.new()
	sensor.space = _space()
	sensor.component_id = "s"
	agent.add_child(sensor)
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	sensor.validations = 0
	for index in 10:
		assert_bool(driver.call("step", environment, {"A": {"00000000:a": 1}}).ok).is_true()
	assert_int(sensor.validations).is_equal(20) # One preflight for act and one for observe.

func test_cached_layout_rejects_renames_reorders_and_resource_changes() -> void:
	var first := _sensor("first")
	var second := _sensor("second")
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	first.component_id = "renamed"
	assert_bool(driver.call("reset", environment).ok).is_false()
	first.component_id = "first"
	assert_bool(driver.call("reset", environment).ok).is_true()
	agent.move_child(second, 0)
	assert_bool(driver.call("reset", environment).ok).is_false()
	agent.move_child(first, 0)
	assert_bool(driver.call("reset", environment).ok).is_true()
	first.space.n = 4
	assert_bool(driver.call("reset", environment).ok).is_false()

func test_in_place_dict_space_changes_are_still_rejected() -> void:
	var sensor := _sensor("s")
	var dictionary := ScholaDictSpace.new()
	dictionary.spaces = {"value": _space()}
	sensor.space = dictionary
	sensor.value = {"value": 1}
	var actuator := _actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	dictionary.spaces["extra"] = _space() # Bypasses Resource.changed.
	assert_bool(driver.call("step", environment, {"A": {"00000000:a": 1}}).ok).is_false()
	assert_int(actuator.calls).is_equal(0)

func test_missing_component_hook_is_detected_before_other_actuators_run() -> void:
	_sensor("s")
	var first := _actuator("first")
	var second := _actuator("second")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	second.set_script(null)
	assert_bool(driver.call("step", environment, {"A": {"00000000:first": 1, "00000001:second": 1}}).ok).is_false()
	assert_int(first.calls).is_equal(0)

func test_invalid_ray_configuration_prevents_any_actuator_dispatch() -> void:
	var sensor := ScholaRayCastSensor3D.new()
	sensor.component_id = "rays"
	agent.add_child(sensor)
	var ray := RayCast3D.new()
	ray.name = "Ray"
	ray.target_position = Vector3(0, 0, -1)
	agent.add_child(ray)
	sensor.add_ray(NodePath("../Ray"))
	var actuator := _actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	sensor.rays.append(NodePath("../Ray")) # No property setter or revision notification.
	assert_bool(driver.call("step", environment, {"A": {"00000000:a": 1}}).ok).is_false()
	assert_int(actuator.calls).is_equal(0)

func test_unrelated_tree_churn_does_not_invalidate_agent_layout() -> void:
	_sensor("s")
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	var revision: int = driver.call("interaction_revision", agent)
	for index in 16:
		var unrelated := Node.new()
		add_child(unrelated)
		unrelated.add_child(Node.new())
		unrelated.free()
	assert_int(driver.call("interaction_revision", agent)).is_equal(revision)
	assert_bool(driver.call("step", environment, {"A": {"00000000:a": 1}}).ok).is_true()

func test_nested_component_order_changes_invalidate_layout() -> void:
	var branch := Node.new()
	agent.add_child(branch)
	var first := _sensor("first", branch)
	var second := _sensor("second", branch)
	_actuator("a")
	assert_bool(driver.call("initialize", environment).ok).is_true()
	assert_bool(driver.call("reset", environment).ok).is_true()
	branch.move_child(second, 0)
	assert_bool(driver.call("reset", environment).ok).is_false()
	branch.move_child(first, 0)
	assert_bool(driver.call("reset", environment).ok).is_true()
