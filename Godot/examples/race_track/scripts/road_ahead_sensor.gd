# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name RaceTrackRoadAheadSensor
extends ScholaSensor

const LANE_HALF_WIDTH := 2.0

@export var body_path: NodePath
@export var view_distance := 60.0


func _init() -> void:
	var box := ScholaBoxSpace.new()
	box.shape = PackedInt32Array([RaceTrackPath.LANES.size()])
	box.low = PackedFloat32Array([0.0])
	box.high = PackedFloat32Array([1.0])
	space = box


func _observe() -> Variant:
	var car := get_node_or_null(body_path) as Node3D
	var track := RaceTrackPath.find_for(self)
	if car == null or track == null:
		return null
	var length := track.curve.get_baked_length()
	var here := track.progress_of(car.global_position)
	var values := PackedFloat32Array([1.0, 1.0, 1.0])
	for node in get_tree().get_nodes_in_group("obstacle"):
		var body := node as CollisionObject3D
		if body == null or body == car or not track.is_ancestor_of(body) or not body.visible or body.collision_layer == 0:
			continue
		var offset: float = body.get_meta("track_offset", 0.0)
		var ahead := fposmod(offset - here, length)
		if ahead > view_distance:
			continue
		var side: float = body.get_meta("track_side", 0.0)
		for lane in RaceTrackPath.LANES.size():
			if absf(side - RaceTrackPath.LANES[lane]) < LANE_HALF_WIDTH:
				values[lane] = minf(values[lane], ahead / view_distance)
	return values
