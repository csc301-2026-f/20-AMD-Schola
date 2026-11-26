# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends Node3D

const OFF := Color(0.4, 0.04, 0.04)
const ON := Color(1.0, 0.08, 0.05)

@export var threshold := 1.0

@onready var car: VehicleBody3D = get_parent()
@onready var glow: OmniLight3D = $Glow
var lit := true
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.emission_enabled = true
	_material.emission = ON
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = _material
	_show(false)


func _process(_delta: float) -> void:
	_show(car.brake > threshold)


func _show(on: bool) -> void:
	if on == lit:
		return
	lit = on
	_material.albedo_color = ON if on else OFF
	_material.emission_energy_multiplier = 4.0 if on else 0.2
	glow.visible = on
