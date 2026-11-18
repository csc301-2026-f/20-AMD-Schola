# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends ScholaAgent

var position := 0


func _observe() -> Variant:
	return position


func _act(action: Variant) -> void:
	position = clampi(position + (-1 if int(action) == 0 else 1), 0, 4)
