# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaFakeCameraSensor
extends ScholaImageSensor

## Deterministic image observations without rendering. Custom data is already CHW.
## Short buffers are zero-padded and long buffers truncated, matching Unreal.
@export var custom_image: PackedFloat32Array = PackedFloat32Array():
	set(value):
		custom_image = value
		update_configuration_warnings()

func _observe() -> Variant:
	if not _get_component_errors().is_empty():
		return null
	var values := custom_image.slice(0, width * height * _channel_count())
	values.resize(width * height * _channel_count())
	return values

func _get_component_errors() -> PackedStringArray:
	var errors := super._get_component_errors()
	if not errors.is_empty():
		return errors
	# Validate the consumed prefix; padding is always valid and excess is ignored.
	for index in mini(custom_image.size(), maxi(0, width * height * _channel_count())):
		if not is_finite(custom_image[index]) or custom_image[index] < 0 or custom_image[index] > 1:
			errors.append("custom_image values must be finite and in [0,1].")
			break
	return errors
