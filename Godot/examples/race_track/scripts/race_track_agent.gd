# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackAgent
extends ScholaAgent

var track: RaceTrackPath
@onready var car: VehicleBody3D = get_parent()
@onready var controls: ScholaVehicleActuator3D = $Controls

func _ready() -> void:
	track = RaceTrackPath.find_in(get_tree())
	place_at_start()

func place_at_start() -> void:
	car.global_transform = track.start_transform()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	controls.reset()
