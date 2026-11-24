# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite


func test_scalar_box_matches_authored_resource_without_expanding_saved_bounds() -> void:
	var generated := ScholaSpaces.box([3, 30, 32], 0, 255, ScholaSpaces.UINT8)
	var authored := ScholaBoxSpace.new()
	authored.shape = PackedInt32Array([3, 30, 32])
	authored.low = PackedFloat32Array([0])
	authored.high = PackedFloat32Array([255])
	authored.dtype = 1
	assert_dict(generated.to_dictionary()).is_equal(authored.to_dictionary())
	assert_int(generated.get_flattened_size()).is_equal(2880)
	assert_int(generated.low.size()).is_equal(1)
	assert_int(generated.high.size()).is_equal(1)
	assert_str(generated.get_definition_error()).is_empty()


func test_box_bounds_support_per_element_mixed_and_unbounded_sides() -> void:
	var bounded := ScholaSpaces.box_bounds([3], [0], [1, 2, 3])
	assert_str(bounded.get_validation_error([0.5, 1.5, 2.5])).is_empty()
	assert_str(bounded.get_validation_error([0.5, 2.5, 2.5])).contains("index 1")
	var unbounded := ScholaSpaces.box_bounds([2])
	assert_int(unbounded.dtype).is_equal(ScholaSpaces.FLOAT32)
	assert_str(unbounded.get_validation_error([-1e30, 1e30])).is_empty()
	var upper_only := ScholaSpaces.box_bounds([2], [], [1])
	assert_str(upper_only.get_validation_error([-1e30, 1])).is_empty()
	assert_str(upper_only.get_validation_error([0, 2])).is_not_empty()


func test_all_factory_kinds_match_direct_resource_definitions() -> void:
	var discrete := ScholaDiscreteSpace.new()
	discrete.n = 5
	var multi_discrete := ScholaMultiDiscreteSpace.new()
	multi_discrete.nvec = PackedInt32Array([3, 5, 2])
	var multi_binary := ScholaMultiBinarySpace.new()
	multi_binary.n = 4
	var generated: Array[ScholaSpace] = [
		ScholaSpaces.discrete(5),
		ScholaSpaces.multi_discrete([3, 5, 2]),
		ScholaSpaces.multi_binary(4),
	]
	var authored: Array[ScholaSpace] = [discrete, multi_discrete, multi_binary]
	for index in range(generated.size()):
		assert_dict(generated[index].to_dictionary()).is_equal(authored[index].to_dictionary())
		assert_str(generated[index].get_definition_error()).is_empty()
		assert_str(generated[index].get_validation_error(generated[index].make_default_value())).is_empty()


func _joint_observations(count: int) -> ScholaDictSpace:
	var joints := {}
	for index in range(count):
		joints["joint_%d" % index] = ScholaSpaces.dict({
			"angle": ScholaSpaces.box([1], -PI, PI),
			"contact": ScholaSpaces.discrete(2),
		})
	return ScholaSpaces.dict(joints)


func test_helpers_build_repeated_nested_spaces_with_existing_order_and_sharing() -> void:
	var child := _joint_observations(3)
	var generated := ScholaSpaces.dict({"z_leg": child, "a_leg": child})
	var authored := ScholaDictSpace.new()
	authored.spaces = {"a_leg": child, "z_leg": child}
	assert_dict(generated.to_dictionary()).is_equal(authored.to_dictionary())
	# Each joint has one angle element and two flattened discrete choices.
	assert_int(generated.get_flattened_size()).is_equal(18)
	assert_str(generated.get_validation_error(generated.make_default_value())).is_empty()
	assert_object(generated.spaces["z_leg"]).is_same(child)
	assert_object(generated.spaces["a_leg"]).is_same(child)
	var replacement := ScholaSpaces.multi_binary(4)
	child.spaces = {"buttons": replacement}
	assert_int(generated.get_flattened_size()).is_equal(8)


func test_invalid_factory_arguments_use_existing_resource_diagnostics() -> void:
	var invalid: Array[ScholaSpace] = [
		ScholaSpaces.box([2], 2, 1),
		ScholaSpaces.box([0], 0, 1),
		ScholaSpaces.box([2], 0, 1, 99),
		ScholaSpaces.box_bounds([3], [0, 0], [1]),
		ScholaSpaces.box_bounds([2], [], [], ScholaSpaces.UINT8),
		ScholaSpaces.discrete(0),
		ScholaSpaces.multi_discrete([3, 0]),
		ScholaSpaces.multi_binary(-1),
		ScholaSpaces.dict({"missing": null}),
		ScholaSpaces.dict({"wrong": 7}),
		ScholaSpaces.dict({7: ScholaSpaces.discrete(2)}),
	]
	for space in invalid:
		assert_object(space).is_not_null()
		assert_str(space.get_definition_error()).is_not_empty()
	var authored := ScholaDiscreteSpace.new()
	authored.n = 0
	assert_str(ScholaSpaces.discrete(0).get_definition_error()).is_equal(authored.get_definition_error())


func test_factory_resources_round_trip_through_standard_serialization() -> void:
	var original := ScholaSpaces.dict({
		"camera": ScholaSpaces.box([1, 30, 32], 0, 255, ScholaSpaces.UINT8),
		"joints": _joint_observations(3),
		"mode": ScholaSpaces.multi_discrete([2, 3]),
		"buttons": ScholaSpaces.multi_binary(4),
	})
	var path := "user://us15_factory_round_trip.tres"
	var saved := ResourceSaver.save(original, path)
	assert_int(saved).is_equal(OK)
	if saved != OK:
		return
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ScholaDictSpace
	DirAccess.remove_absolute(path)
	assert_object(loaded).is_not_null()
	if loaded == null:
		return
	assert_dict(loaded.to_dictionary()).is_equal(original.to_dictionary())
	assert_str(loaded.get_definition_error()).is_empty()
	assert_str(loaded.get_validation_error(loaded.make_default_value())).is_empty()
