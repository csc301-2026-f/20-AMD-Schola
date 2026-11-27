# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
class_name RaceTrackAgent
extends ScholaAgent

var track: RaceTrackPath
@onready var car: ArcadeVehicle = get_parent()
@onready var controls: ScholaVehicleActuator3D = $Controls
@onready var rays: ScholaRayCastSensor3D = $Rays

func _ready() -> void:
	track = RaceTrackPath.find_for(self)
	$Track.path_path = $Track.get_path_to(track)
	place_at_start()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_H:
		rays.draw_debug = not rays.draw_debug

func place_at_start() -> void:
	place(track.start_transform())

func place(pose: Transform3D) -> void:
	car.global_transform = pose
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	controls.reset()
	car.reset_handling()
