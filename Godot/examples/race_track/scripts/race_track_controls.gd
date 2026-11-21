# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name RaceTrackControls
extends ScholaVehicleActuator3D

var action := PackedFloat32Array([0.0, 0.0])


func _act(value: Variant) -> void:
	action = value
	super(value)
