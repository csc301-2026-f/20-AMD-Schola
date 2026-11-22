# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name RaceTrackRoadAheadSensor
extends ScholaSensor

const LANES: Array[float] = [2.5, 0.0, -2.5]
const LANE_HALF_WIDTH := 2.0

@export var body_path: NodePath
@export var view_distance := 60.0


func _init() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([LANES.size()])
	box.low = PackedFloat32Array([0.0])
	box.high = PackedFloat32Array([1.0])
	space = box


func _observe() -> Variant:
	var car := get_node_or_null(body_path) as Node3D
	var track := RaceTrackPath.find_in(get_tree())
	if car == null or track == null:
		return null
	var length := track.curve.get_baked_length()
	var here := track.progress_of(car.global_position)
	var values := PackedFloat32Array([1.0, 1.0, 1.0])
	for node in get_tree().get_nodes_in_group("obstacle"):
		var body := node as CollisionObject3D
		if body == null or body == car or not body.visible or body.collision_layer == 0:
			continue
		var offset := track.progress_of(body.global_position)
		var ahead := fposmod(offset - here, length)
		if ahead > view_distance:
			continue
		var left := Vector3.UP.cross(track.direction_at(offset)).normalized()
		var side := (body.global_position - track.center_at(offset)).dot(left)
		for lane in LANES.size():
			if absf(side - LANES[lane]) < LANE_HALF_WIDTH:
				values[lane] = minf(values[lane], ahead / view_distance)
	return values
