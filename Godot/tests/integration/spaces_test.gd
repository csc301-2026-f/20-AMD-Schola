# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

class_name SpacesIntegrationTest
extends GdUnitTestSuite


func _box(low: PackedFloat32Array, high: PackedFloat32Array, shape := PackedInt32Array()) -> ScholaBoxSpace:
	var space := ScholaBoxSpace.new()
	space.low = low
	space.high = high
	space.shape = shape
	return space


func _discrete(n: int) -> ScholaDiscreteSpace:
	var space := ScholaDiscreteSpace.new()
	space.n = n
	return space


func _dict() -> ScholaDictSpace:
	var multi_discrete := ScholaMultiDiscreteSpace.new()
	multi_discrete.nvec = PackedInt32Array([3, 2])
	var multi_binary := ScholaMultiBinarySpace.new()
	multi_binary.n = 3
	var space := ScholaDictSpace.new()
	space.spaces = {
		"position": _box(PackedFloat32Array([-1.0]), PackedFloat32Array([1.0]), PackedInt32Array([2])),
		"mode": _discrete(4),
		"grid": multi_discrete,
		"buttons": multi_binary,
	}
	return space


func test_space_resources_are_registered() -> void:
	for name in ["ScholaSpace", "ScholaBoxSpace", "ScholaDiscreteSpace", "ScholaMultiDiscreteSpace", "ScholaMultiBinarySpace", "ScholaDictSpace"]:
		assert_bool(ClassDB.class_exists(name)).is_true()


func test_default_values_round_trip_for_every_kind() -> void:
	var spaces: Array[ScholaSpace] = [
		_box(PackedFloat32Array([1.0]), PackedFloat32Array([2.0]), PackedInt32Array([2, 2])),
		_discrete(3),
		_dict(),
	]
	for space in spaces:
		assert_str(space.get_definition_error()).is_empty()
		assert_str(space.get_validation_error(space.make_default_value())).is_empty()


func test_empty_box_bounds_are_unbounded() -> void:
	var space := _box(PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array([2]))
	assert_str(space.get_definition_error()).is_empty()
	assert_str(space.get_validation_error(PackedFloat32Array([-1e30, 1e30]))).is_empty()


func test_single_box_bound_applies_to_every_element() -> void:
	var space := _box(PackedFloat32Array([0.0]), PackedFloat32Array([1.0, 2.0, 3.0]))
	assert_str(space.get_definition_error()).is_empty()
	assert_str(space.get_validation_error(PackedFloat32Array([0.5, 1.5, 2.5]))).is_empty()
	assert_str(space.get_validation_error(PackedFloat32Array([0.5, -1.0, 2.5]))).contains("index 1")


func test_box_accepts_number_arrays() -> void:
	var space := _box(PackedFloat32Array([-1.0]), PackedFloat32Array([1.0]), PackedInt32Array([2]))
	assert_str(space.get_validation_error([0.5, -1])).is_empty()
	assert_str(space.get_validation_error(PackedFloat64Array([0.5, 0.25]))).is_empty()
	assert_str(space.get_validation_error([0.5, "x"])).contains("Array element 1")


func test_wrong_value_names_expected_type_and_size() -> void:
	var space := _box(PackedFloat32Array([-1.0]), PackedFloat32Array([1.0]), PackedInt32Array([4]))
	assert_str(space.get_validation_error([0.1, 0.2, 0.3])).is_equal("expected PackedFloat32Array of size 4 for Box(shape=[4]), got Array of size 3")


func test_discrete_rejects_out_of_range_values() -> void:
	var space := _discrete(4)
	assert_str(space.get_validation_error(3)).is_empty()
	assert_str(space.get_validation_error(4)).contains("outside [0, 4)")
	assert_str(space.get_validation_error(1 << 40)).contains("32-bit")
	assert_str(space.get_validation_error(1.0)).contains("expected int")


func test_dict_accepts_string_name_keys_and_names_failing_key() -> void:
	var space := _dict()
	var value: Dictionary = space.make_default_value()
	var renamed := {}
	for key in value:
		renamed[StringName(key)] = value[key]
	assert_str(space.get_validation_error(renamed)).is_empty()

	value["mode"] = 9
	assert_str(space.get_validation_error(value)).contains("at 'mode'")
	value.erase("mode")
	assert_str(space.get_validation_error(value)).contains("missing key 'mode'")


func test_dict_reports_unassigned_entry() -> void:
	var space := ScholaDictSpace.new()
	space.spaces = {"position": null}
	assert_str(space.get_definition_error()).contains("at 'position'")


func test_dict_that_contains_itself_reports_a_cycle() -> void:
	var space := ScholaDictSpace.new()
	space.spaces = {"mode": _discrete(2), "self": space}
	assert_str(space.get_definition_error()).contains("at 'self': Dict contains itself")
	assert_str(space.get_validation_error({"mode": 0})).is_not_empty()


func test_dict_used_twice_is_not_a_cycle() -> void:
	var shared := ScholaDictSpace.new()
	shared.spaces = {"mode": _discrete(2)}
	var space := ScholaDictSpace.new()
	space.spaces = {"left": shared, "right": shared}
	assert_str(space.get_definition_error()).is_empty()


func test_box_rejects_unknown_dtype_and_oversized_shape() -> void:
	var space := _box(PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array([2]))
	space.dtype = 99
	assert_str(space.get_definition_error()).contains("dtype 99")
	assert_str(space.to_dictionary()["dtype"]).is_equal("unknown")
	var huge := _box(PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array([100000, 100000, 100000]))
	assert_str(huge.get_definition_error()).contains("elements")
