# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends ScholaAgent

@export_range(1, 1920) var camera_width := 640
@export_range(1, 1080) var camera_height := 480
@export_range(1, 8) var limb_count := 2
@export_range(1, 8) var joints_per_limb := 3

var definition_calls := 0
var action_count := 0
var last_action: Dictionary = {}
var _pixels := PackedFloat32Array()


func _joint_observation_space() -> ScholaDictSpace:
	return ScholaSpaces.dict({
		"angle": ScholaSpaces.box([1], -PI, PI),
		"contact": ScholaSpaces.multi_binary(1),
	})


func _limb_observation_space() -> ScholaDictSpace:
	var joints := {}
	for joint in range(joints_per_limb):
		joints["joint_%d" % joint] = _joint_observation_space()
	return ScholaSpaces.dict(joints)


func _limb_action_space() -> ScholaDictSpace:
	var joints := {}
	for joint in range(joints_per_limb):
		joints["joint_%d" % joint] = ScholaSpaces.discrete(3)
	return ScholaSpaces.dict({
		"joints": ScholaSpaces.dict(joints),
		"gripper": ScholaSpaces.multi_binary(1),
	})


func _define_spaces() -> ScholaSpaceDefinition:
	definition_calls += 1
	var observations := {}
	var actions := {}
	for limb in range(limb_count):
		var key := "limb_%d" % limb
		observations[key] = _limb_observation_space()
		actions[key] = _limb_action_space()
	return ScholaSpaceDefinition.create(
		ScholaSpaces.dict({
			"camera": ScholaSpaces.box(
				[camera_height, camera_width, 3], 0, 255, ScholaSpaces.UINT8
			),
			"limbs": ScholaSpaces.dict(observations),
		}),
		ScholaSpaces.dict({
			"movement": ScholaSpaces.box([3], -1, 1),
			"limbs": ScholaSpaces.dict(actions),
		}),
	)


func _observe() -> Variant:
	# A flat RGB pattern, not an image captured from a Camera3D. Box values use
	# float32 storage at the native boundary even with a uint8 space definition.
	if _pixels.is_empty():
		_pixels.resize(camera_height * camera_width * 3)
		for offset in range(0, _pixels.size(), 3):
			_pixels[offset] = 255
			_pixels[offset + 1] = 128
			_pixels[offset + 2] = 64
	var limbs := {}
	for limb in range(limb_count):
		var joints := {}
		for joint in range(joints_per_limb):
			joints["joint_%d" % joint] = {
				"angle": PackedFloat32Array([sin(action_count * 0.1)]),
				"contact": PackedByteArray([action_count % 2]),
			}
		limbs["limb_%d" % limb] = joints
	return {"camera": _pixels, "limbs": limbs}


func _act(action: Variant) -> void:
	# Record a validated action; this example does not simulate robot physics.
	last_action = action
	action_count += 1


func reset_sample() -> void:
	action_count = 0
	last_action = {}


func sample_action() -> Dictionary:
	var limbs := {}
	for limb in range(limb_count):
		var joints := {}
		for joint in range(joints_per_limb):
			joints["joint_%d" % joint] = (action_count + joint) % 3
		limbs["limb_%d" % limb] = {
			"joints": joints,
			"gripper": PackedByteArray([action_count % 2]),
		}
	return {"movement": PackedFloat32Array([0.5, 0, -0.5]), "limbs": limbs}
