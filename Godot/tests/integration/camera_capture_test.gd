# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const TOLERANCE := 0.5 / 255.0
const SOURCE_ERROR := "Camera sources must reference SubViewport nodes."

var agent: ScholaAgent


func before(
	_do_skip := DisplayServer.get_name() == "headless",
	_skip_reason := "The real camera needs a rendering display; run with --rendering-method gl_compatibility or mobile."
) -> void:
	pass


func before_test() -> void:
	agent = auto_free(ScholaAgent.new())
	add_child(agent)


func test_8_bit_colors_are_divided_by_255() -> void:
	var sensor := _camera(_solid(Color8(128, 64, 255)), 15)
	await _render()
	_assert_values(sensor._observe(), _planes([128, 64, 255, 255]))


func test_non_square_image_keeps_rows_and_columns() -> void:
	var colors: Array[Color] = []
	for y in 2:
		for x in 3:
			colors.append(Color8(40 * (x + 1), 100 * (y + 1), 0))
	var sensor := _camera(_viewport(Vector2i(3, 2), colors), 3)
	await _render()
	_assert_values(sensor._observe(), [40, 80, 120, 40, 80, 120, 100, 100, 100, 200, 200, 200])


func test_selected_channels_keep_rgba_order() -> void:
	var viewport := _viewport(Vector2i(2, 2), [Color8(10, 20, 30), Color8(40, 50, 60), Color8(70, 80, 90), Color8(100, 110, 120)])
	var red := _camera(viewport, 1)
	var red_green := _camera(viewport, 3)
	var green_alpha := _camera(viewport, 10)
	await _render()
	_assert_values(red._observe(), [10, 40, 70, 100])
	_assert_values(red_green._observe(), [10, 40, 70, 100, 20, 50, 80, 110])
	_assert_values(green_alpha._observe(), [20, 50, 80, 110, 255, 255, 255, 255])


func test_repeated_captures_return_the_latest_completed_frame() -> void:
	var viewport := _solid(Color8(200, 0, 0))
	var pixel := viewport.get_child(0) as ColorRect
	var sensor := _camera(viewport, 7)
	for color: Color in [Color8(200, 0, 0), Color8(0, 150, 0), Color8(0, 0, 100), Color8(30, 60, 90)]:
		pixel.color = color
		await _render()
		var first: PackedFloat32Array = sensor._observe()
		_assert_values(first, _planes([color.r8, color.g8, color.b8]))
		assert_array(Array(sensor._observe())).is_equal(Array(first))


func test_capture_before_the_next_frame_returns_the_previous_frame() -> void:
	var viewport := _solid(Color8(200, 0, 0))
	var sensor := _camera(viewport, 7)
	await _render()
	(viewport.get_child(0) as ColorRect).color = Color8(0, 0, 200)
	_assert_values(sensor._observe(), _planes([200, 0, 0]))
	await _render()
	_assert_values(sensor._observe(), _planes([0, 0, 200]))


func test_removed_viewport_stops_observations() -> void:
	var viewport := _solid(Color8(200, 0, 0))
	var sensor := _camera(viewport, 7)
	await _render()
	_assert_values(sensor._observe(), _planes([200, 0, 0]))
	viewport.queue_free()
	await get_tree().process_frame
	assert_that(sensor._observe()).is_null()
	assert_bool(sensor.get_configuration_errors().has(SOURCE_ERROR)).is_true()


func _solid(color: Color) -> SubViewport:
	return _viewport(Vector2i(2, 2), [color], Vector2(2, 2))


func _viewport(size: Vector2i, colors: Array, pixel_size := Vector2.ONE) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for index in colors.size():
		var pixel := ColorRect.new()
		pixel.position = Vector2(index % size.x, index / size.x)
		pixel.size = pixel_size
		pixel.color = colors[index]
		viewport.add_child(pixel)
	agent.add_child(viewport)
	return viewport


func _camera(viewport: SubViewport, channels: int) -> ScholaCameraSensor:
	var sensor := ScholaCameraSensor.new()
	sensor.width = viewport.size.x
	sensor.height = viewport.size.y
	sensor.enabled_channels = channels
	agent.add_child(sensor)
	sensor.viewport_path = sensor.get_path_to(viewport)
	return sensor


func _render() -> void:
	for frame in 3:
		await get_tree().process_frame
		RenderingServer.force_draw(false)


func _planes(channel_bytes: Array) -> Array:
	var result := []
	for value in channel_bytes:
		for pixel in 4:
			result.append(value)
	return result


func _assert_values(values: Variant, expected_bytes: Array) -> void:
	assert_that(values).is_not_null()
	var actual := values as PackedFloat32Array
	assert_int(actual.size()).is_equal(expected_bytes.size())
	for index in mini(actual.size(), expected_bytes.size()):
		assert_float(actual[index]).is_equal_approx(expected_bytes[index] / 255.0, TOLERANCE)
