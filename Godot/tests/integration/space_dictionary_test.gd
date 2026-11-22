# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

# US3: the training extension never sees the runtime's space resources. It gets
# the Dictionaries ScholaTrainingHost.define() reports and rebuilds each space
# with dictionary_to_space(). These tests check that rebuild is exact, and that
# a malformed Dictionary is refused with a message naming the bad field.
extends GdUnitTestSuite

const INVALID_DATA := 3

var _driver: RefCounted


func before_test() -> void:
	assert_bool(ClassDB.class_exists("ScholaEnvironmentTestDriver"))\
		.override_failure_message("Build with integration_tests=yes to run the space dictionary suite.")\
		.is_true()
	_driver = ClassDB.instantiate("ScholaEnvironmentTestDriver")


func after_test() -> void:
	_driver = null


# --- Helpers ---------------------------------------------------------------


func _box(shape: Array, low: Array, high: Array, dtype := 0) -> ScholaBoxSpace:
	var space := ScholaBoxSpace.new()
	space.shape = PackedInt32Array(shape)
	space.low = PackedFloat32Array(low)
	space.high = PackedFloat32Array(high)
	space.dtype = dtype
	return space


func _discrete(n: int) -> ScholaDiscreteSpace:
	var space := ScholaDiscreteSpace.new()
	space.n = n
	return space


func _multi_discrete(nvec: Array) -> ScholaMultiDiscreteSpace:
	var space := ScholaMultiDiscreteSpace.new()
	space.nvec = PackedInt32Array(nvec)
	return space


func _multi_binary(n: int) -> ScholaMultiBinarySpace:
	var space := ScholaMultiBinarySpace.new()
	space.n = n
	return space


func _dict(spaces: Dictionary) -> ScholaDictSpace:
	var space := ScholaDictSpace.new()
	space.spaces = spaces
	return space


# Sends a host-style Dictionary through dictionary_to_space() and back.
func _round_trip(written: Dictionary) -> Dictionary:
	var result: Dictionary = _driver.call("space_from_dictionary", written)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	return result.get("space", {})


# --- Exact round trips -------------------------------------------------------


func test_every_space_type_round_trips_exactly() -> void:
	var spaces: Array[ScholaSpace] = [
		_box([2, 3], [-1.5], [2.5]),
		_box([4], [0], [255], 1),
		_discrete(5),
		_multi_discrete([3, 2, 4]),
		_multi_binary(6),
	]
	for space in spaces:
		var written := space.to_dictionary()
		assert_dict(_round_trip(written)).is_equal(written)


func test_unbounded_box_sides_survive_as_null() -> void:
	# Empty bounds mean unbounded; the Dictionary writes those sides as null.
	var written := _box([3], [], []).to_dictionary()
	assert_object(written.low[0]).is_null()

	assert_dict(_round_trip(written)).is_equal(written)


func test_nested_dict_round_trips_in_gymnasium_key_order() -> void:
	var arm := _dict({"shoulder": _box([1], [-3.14], [3.14]), "gripper": _multi_binary(1)})
	var written := _dict({"camera": _box([8, 8, 3], [0], [1]), "arm": arm, "mode": _discrete(3)}).to_dictionary()

	var read := _round_trip(written)

	# Core Dict spaces sort entries by key, like gymnasium.spaces.Dict, so the
	# flattened layout Python sees doesn't depend on declaration order.
	assert_dict(read).is_equal(written)
	assert_array(read.spaces.keys()).contains_exactly(["arm", "camera", "mode"])
	assert_array(read.spaces.arm.spaces.keys()).contains_exactly(["gripper", "shoulder"])


# --- Malformed input is refused -----------------------------------------------


func test_malformed_dictionaries_name_the_problem() -> void:
	var box := _box([2], [0], [1]).to_dictionary()
	var float_shape := box.duplicate(true)
	float_shape.shape = [2.0]
	var text_bound := box.duplicate(true)
	text_bound.low = ["zero", 0]
	# Each case: [what the host would have sent, part of the expected error].
	var cases := [
		["not a dictionary", "must be a Dictionary"],
		[{"n": 3}, "type must be a String"],
		[{"type": "Tuple"}, "unknown type 'Tuple'"],
		[{"type": "Discrete", "n": 2.5}, "n must be a 32-bit int"],
		[{"type": "Discrete", "n": 4294967296}, "n must be a 32-bit int"],
		[{"type": "MultiDiscrete", "nvec": "3,3"}, "nvec must be an Array of ints"],
		[float_shape, "shape[0] must be a 32-bit int"],
		[text_bound, "low[0] must be a number or null"],
		[{"type": "Box", "low": [0], "high": [1], "shape": [1], "dtype": "float128"}, "unknown dtype 'float128'"],
		[{"type": "Dict", "spaces": {7: {"type": "Discrete", "n": 2}}}, "Dict keys must be Strings"],
		[{"type": "Dict", "spaces": {"arm": {"type": "Discrete", "n": "two"}}}, "space 'arm'"],
		# Well-formed fields, but an invalid space: check_definition() still runs.
		[{"type": "Discrete", "n": 0}, "must be positive"],
	]
	for entry in cases:
		var result: Dictionary = _driver.call("space_from_dictionary", entry[0])
		assert_bool(result.ok).override_failure_message("accepted: " + str(entry[0])).is_false()
		assert_int(result.code).is_equal(INVALID_DATA)
		assert_str(result.message).contains(entry[1])
