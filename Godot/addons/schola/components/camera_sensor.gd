# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaCameraSensor
extends ScholaImageSensor

## Reads the latest completed viewport frame, on the main thread. The lifecycle
## owner must wait for frame_post_draw before the first reset/observation.
## Depth uses a separate viewport encoding normalized linear depth in red.
enum CaptureMode { COLOR, DEPTH, COLOR_DEPTH }
@export var viewport_path: NodePath:
	set(value):
		viewport_path = value
		update_configuration_warnings()
@export var depth_viewport_path: NodePath:
	set(value):
		depth_viewport_path = value
		update_configuration_warnings()
@export var capture_mode: CaptureMode = CaptureMode.COLOR:
	set(value):
		capture_mode = value
		_refresh_space()

func _channel_count() -> int:
	if capture_mode == CaptureMode.DEPTH:
		return 1
	return super._channel_count() + int(capture_mode == CaptureMode.COLOR_DEPTH)

func _valid_channels() -> bool:
	return (enabled_channels >= 0 and enabled_channels <= 15) if capture_mode == CaptureMode.DEPTH else super._valid_channels()

func _get_component_errors() -> PackedStringArray:
	var errors := super._get_component_errors()
	if capture_mode < CaptureMode.COLOR or capture_mode > CaptureMode.COLOR_DEPTH:
		errors.append("capture_mode must be Color, Depth or ColorDepth.")
	var paths: Array[NodePath] = []
	if capture_mode != CaptureMode.DEPTH:
		paths.append(viewport_path)
	if capture_mode != CaptureMode.COLOR:
		paths.append(depth_viewport_path)
	for path in paths:
		var viewport := get_node_or_null(path) as SubViewport
		if viewport == null:
			errors.append("Camera sources must reference SubViewport nodes.")
		elif viewport.size != Vector2i(width, height):
			errors.append("Source viewport size must match the image width and height.")
	if DisplayServer.get_name() == "headless":
		errors.append("Camera readback requires a rendering display; use ScholaFakeCameraSensor for headless runs.")
	return errors

func _read(path: NodePath, channels: PackedInt32Array) -> PackedFloat32Array:
	var viewport := get_node_or_null(path) as SubViewport
	if viewport == null:
		return PackedFloat32Array()
	var texture := viewport.get_texture()
	return _image_values(texture.get_image(), channels) if texture != null else PackedFloat32Array()

func _observe() -> Variant:
	if not _get_component_errors().is_empty():
		return null
	var values := PackedFloat32Array()
	if capture_mode != CaptureMode.DEPTH:
		values = _read(viewport_path, _channel_indices())
		if values.size() != width * height * _channel_indices().size():
			return null
	if capture_mode != CaptureMode.COLOR:
		var depth := _read(depth_viewport_path, PackedInt32Array([0]))
		if depth.size() != width * height:
			return null
		values.append_array(depth)
	return values
