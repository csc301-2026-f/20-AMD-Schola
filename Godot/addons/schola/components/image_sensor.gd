# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaImageSensor
extends ScholaSensor

## Common bounded CHW image layout. R/G/B/A channels retain this order.
const MAX_VALUES := 4194304
@export_range(1, 2048) var width: int = 128:
	set(value):
		width = value
		_refresh_space()
@export_range(1, 2048) var height: int = 128:
	set(value):
		height = value
		_refresh_space()
@export_flags("R", "G", "B", "A") var enabled_channels: int = 7:
	set(value):
		enabled_channels = value
		_refresh_space()
var readback_error := ""

func _init() -> void:
	_refresh_space()

func _channel_indices() -> PackedInt32Array:
	var result := PackedInt32Array()
	for channel in 4:
		if enabled_channels & (1 << channel):
			result.append(channel)
	return result

func _channel_count() -> int:
	return _channel_indices().size()

func _valid_channels() -> bool:
	return enabled_channels >= 1 and enabled_channels <= 15

func _valid_dimensions() -> bool:
	return width >= 1 and width <= 2048 and height >= 1 and height <= 2048 and width * height * _channel_count() <= MAX_VALUES

func _expected_space() -> ScholaBoxSpace:
	if not _valid_dimensions():
		return ScholaComponentSpace.box(PackedInt32Array([0]), PackedFloat32Array([0]), PackedFloat32Array([1]))
	return ScholaComponentSpace.box(PackedInt32Array([_channel_count(), height, width]), PackedFloat32Array([0]), PackedFloat32Array([1]))

func _refresh_space() -> void:
	space = _expected_space()
	update_configuration_warnings()

func _get_component_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _valid_dimensions():
		errors.append("Image dimensions must be 1..2048 and total values must not exceed %d." % MAX_VALUES)
	if not _valid_channels():
		errors.append("Enable at least one RGBA channel using only the four channel flags.")
	if not ScholaComponentSpace.matches(space, _expected_space()):
		errors.append("Image space must match its channels and dimensions; reassign width to regenerate it.")
	return errors

## Converts uncompressed RGB8/RGBA8 to flattened [C,H,W], with no resizing.
## Other formats fail capture; no decompression or format conversion is attempted.
func _image_values(image: Image, indices: PackedInt32Array) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if image == null or image.is_empty() or image.get_width() != width or image.get_height() != height:
		return values
	if image.is_compressed() or image.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
		_report_readback_format(image.get_format())
		return values
	readback_error = ""
	values.resize(indices.size() * width * height)
	var offset := 0
	for channel in indices:
		for y in height:
			for x in width:
				values[offset] = image.get_pixel(x, y)[channel]
				offset += 1
	return values

func _report_readback_format(format: int) -> void:
	var names := ClassDB.class_get_enum_constants("Image", "Format")
	var message := "%s._observe: readback format %s is not supported; use an uncompressed RGB8 or RGBA8 viewport without HDR 2D." % [get_script().get_global_name(), names[format] if format >= 0 and format < names.size() else str(format)]
	if message != readback_error:
		readback_error = message
		push_error(message)
