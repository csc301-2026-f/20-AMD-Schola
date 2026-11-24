# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const FLOAT32 := 0
const DIMENSION_ERROR := "Image dimensions must be 1..2048 and total values must not exceed 4194304."
const CHANNEL_ERROR := "Enable at least one RGBA channel using only the four channel flags."
const SOURCE_ERROR := "Camera sources must reference SubViewport nodes."
const SIZE_ERROR := "Source viewport size must match the image width and height."
const HEADLESS_ERROR := "Camera readback requires a rendering display; use ScholaFakeCameraSensor for headless runs."
const MINIMUM_ERROR := "Camera images must be at least 2x2 pixels because Godot SubViewports are never smaller."
const UPDATE_ERROR := "Source viewports must render for each capture; set render_target_update_mode to Always, or to Once before each capture."
const HDR_ERROR := "Source viewports must not use HDR 2D, which produces linear values above 1."

var agent: ScholaAgent


func before_test() -> void:
	agent = auto_free(ScholaAgent.new())
	add_child(agent)


func test_image_space_is_channels_by_height_by_width(
	width: int,
	height: int,
	channels: int,
	expected: Array,
	_test_parameters := [
		[128, 128, 7, [3, 128, 128]],
		[256, 256, 15, [4, 256, 256]],
		[64, 64, 1, [1, 64, 64]],
		[512, 512, 3, [2, 512, 512]],
		[320, 240, 7, [3, 240, 320]],
	]
) -> void:
	for sensor: ScholaImageSensor in [_camera(width, height, channels), _fake(width, height, channels)]:
		var space := sensor.space as ScholaBoxSpace
		assert_object(space).is_not_null()
		assert_array(Array(space.shape)).is_equal(expected)
		assert_int(space.dtype).is_equal(FLOAT32)
		assert_int(space.get_flattened_size()).is_equal(expected[0] * expected[1] * expected[2])


func test_image_values_are_bounded_from_zero_to_one() -> void:
	var space: ScholaBoxSpace = _fake(4, 2, 7).space
	var values := PackedFloat32Array()
	values.resize(space.get_flattened_size())
	values.fill(0.0)
	assert_str(space.get_validation_error(values)).is_empty()
	values.fill(1.0)
	assert_str(space.get_validation_error(values)).is_empty()
	values[5] = 1.01
	assert_str(space.get_validation_error(values)).is_not_empty()
	values[5] = -0.01
	assert_str(space.get_validation_error(values)).is_not_empty()


func test_enabled_channels_set_the_channel_count(
	channels: int,
	expected: int,
	_test_parameters := [[15, 4], [7, 3], [1, 1], [3, 2], [5, 2], [8, 1], [10, 2]]
) -> void:
	assert_array(Array(_camera(8, 4, channels).space.shape)).is_equal([expected, 4, 8])
	assert_array(Array(_fake(8, 4, channels).space.shape)).is_equal([expected, 4, 8])


func test_depth_adds_one_channel_to_the_selected_colors() -> void:
	var cases := [
		[ScholaCameraSensor.CaptureMode.DEPTH, 0, 1],
		[ScholaCameraSensor.CaptureMode.DEPTH, 15, 1],
		[ScholaCameraSensor.CaptureMode.COLOR_DEPTH, 7, 4],
		[ScholaCameraSensor.CaptureMode.COLOR_DEPTH, 1, 2],
	]
	for case in cases:
		var sensor := _camera(8, 4, case[1])
		sensor.capture_mode = case[0]
		assert_array(Array(sensor.space.shape)).is_equal([case[2], 4, 8])
		assert_bool(sensor.get_configuration_errors().has(CHANNEL_ERROR)).is_false()


func test_fake_camera_observations_match_its_space() -> void:
	var sensor := _fake(3, 2, 3)
	var zeros: PackedFloat32Array = sensor._observe()
	assert_int(zeros.size()).is_equal(sensor.space.get_flattened_size())
	assert_bool(Array(zeros).all(func(value: float) -> bool: return value == 0.0)).is_true()
	var image := PackedFloat32Array()
	for index in 12:
		image.append(index / 12.0)
	sensor.custom_image = image
	var values: PackedFloat32Array = sensor._observe()
	assert_array(Array(values)).is_equal(Array(image))
	assert_str(sensor.space.get_validation_error(values)).is_empty()


func test_invalid_dimensions_and_channels_are_reported() -> void:
	assert_bool(_fake(0, 4, 7).get_configuration_errors().has(DIMENSION_ERROR)).is_true()
	assert_bool(_fake(2048, 2048, 1).get_configuration_errors().has(DIMENSION_ERROR)).is_false()
	assert_bool(_fake(2048, 2048, 3).get_configuration_errors().has(DIMENSION_ERROR)).is_true()
	assert_bool(_fake(8, 4, 0).get_configuration_errors().has(CHANNEL_ERROR)).is_true()
	assert_bool(_fake(8, 4, 16).get_configuration_errors().has(CHANNEL_ERROR)).is_true()
	assert_bool(_camera(8, 4, 0).get_configuration_errors().has(CHANNEL_ERROR)).is_true()
	var color_depth := _camera(8, 4, 0)
	color_depth.capture_mode = ScholaCameraSensor.CaptureMode.COLOR_DEPTH
	assert_bool(color_depth.get_configuration_errors().has(CHANNEL_ERROR)).is_true()


func test_camera_sources_must_be_subviewports_of_the_image_size() -> void:
	var sensor := _camera(8, 4, 7)
	assert_bool(sensor.get_configuration_errors().has(SOURCE_ERROR)).is_true()
	var node := Node3D.new()
	node.name = "NotAViewport"
	agent.add_child(node)
	sensor.viewport_path = sensor.get_path_to(node)
	assert_bool(sensor.get_configuration_errors().has(SOURCE_ERROR)).is_true()
	sensor.viewport_path = sensor.get_path_to(_viewport("Transposed", Vector2i(4, 8)))
	var errors := sensor.get_configuration_errors()
	assert_bool(errors.has(SOURCE_ERROR)).is_false()
	assert_bool(errors.has(SIZE_ERROR)).is_true()
	sensor.viewport_path = sensor.get_path_to(_viewport("Color", Vector2i(8, 4)))
	errors = sensor.get_configuration_errors()
	assert_bool(errors.has(SOURCE_ERROR) or errors.has(SIZE_ERROR)).is_false()
	sensor.capture_mode = ScholaCameraSensor.CaptureMode.COLOR_DEPTH
	assert_bool(sensor.get_configuration_errors().has(SOURCE_ERROR)).is_true()
	sensor.depth_viewport_path = sensor.get_path_to(_viewport("Depth", Vector2i(8, 4)))
	errors = sensor.get_configuration_errors()
	assert_bool(errors.has(SOURCE_ERROR) or errors.has(SIZE_ERROR)).is_false()
	sensor.capture_mode = ScholaCameraSensor.CaptureMode.DEPTH
	sensor.viewport_path = NodePath()
	errors = sensor.get_configuration_errors()
	assert_bool(errors.has(SOURCE_ERROR) or errors.has(SIZE_ERROR)).is_false()


func test_real_camera_reports_that_headless_runs_cannot_render(
	_do_skip := DisplayServer.get_name() != "headless",
	_skip_reason := "Only a headless run reports this error."
) -> void:
	var sensor := _camera(8, 4, 7)
	sensor.viewport_path = sensor.get_path_to(_viewport("Color", Vector2i(8, 4)))
	assert_array(Array(sensor.get_configuration_errors())).contains_exactly([HEADLESS_ERROR])
	assert_that(sensor._observe()).is_null()


func test_real_camera_images_must_be_at_least_2_by_2() -> void:
	for size in [Vector2i(1, 4), Vector2i(4, 1), Vector2i(1, 1)]:
		assert_bool(_camera(size.x, size.y, 7).get_configuration_errors().has(MINIMUM_ERROR)).is_true()
	assert_bool(_camera(2, 2, 7).get_configuration_errors().has(MINIMUM_ERROR)).is_false()
	assert_bool(_fake(1, 1, 7).get_configuration_errors().has(MINIMUM_ERROR)).is_false()


func test_viewports_that_stop_rendering_are_reported() -> void:
	var sensor := _camera(8, 4, 7)
	var color := _viewport("Color", Vector2i(8, 4))
	sensor.viewport_path = sensor.get_path_to(color)
	var cases := [
		[SubViewport.UPDATE_DISABLED, true],
		[SubViewport.UPDATE_WHEN_VISIBLE, true],
		[SubViewport.UPDATE_ONCE, false],
		[SubViewport.UPDATE_WHEN_PARENT_VISIBLE, false],
		[SubViewport.UPDATE_ALWAYS, false],
	]
	for case in cases:
		color.render_target_update_mode = case[0]
		assert_bool(sensor.get_configuration_errors().has(UPDATE_ERROR)).is_equal(case[1])
	var depth := _viewport("Depth", Vector2i(8, 4))
	depth.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sensor.depth_viewport_path = sensor.get_path_to(depth)
	sensor.capture_mode = ScholaCameraSensor.CaptureMode.COLOR_DEPTH
	assert_bool(sensor.get_configuration_errors().has(UPDATE_ERROR)).is_true()


func test_hdr_viewports_are_reported() -> void:
	var sensor := _camera(8, 4, 7)
	var color := _viewport("Color", Vector2i(8, 4))
	sensor.viewport_path = sensor.get_path_to(color)
	assert_bool(sensor.get_configuration_errors().has(HDR_ERROR)).is_false()
	color.use_hdr_2d = true
	assert_bool(sensor.get_configuration_errors().has(HDR_ERROR)).is_true()
	color.use_hdr_2d = false
	var depth := _viewport("Depth", Vector2i(8, 4))
	depth.use_hdr_2d = true
	sensor.depth_viewport_path = sensor.get_path_to(depth)
	sensor.capture_mode = ScholaCameraSensor.CaptureMode.DEPTH
	assert_bool(sensor.get_configuration_errors().has(HDR_ERROR)).is_true()


func _camera(width: int, height: int, channels: int) -> ScholaCameraSensor:
	var sensor := ScholaCameraSensor.new()
	sensor.width = width
	sensor.height = height
	sensor.enabled_channels = channels
	agent.add_child(sensor)
	return sensor


func _fake(width: int, height: int, channels: int) -> ScholaFakeCameraSensor:
	var sensor := ScholaFakeCameraSensor.new()
	sensor.width = width
	sensor.height = height
	sensor.enabled_channels = channels
	agent.add_child(sensor)
	return sensor


func _viewport(viewport_name: String, size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	agent.add_child(viewport)
	return viewport
