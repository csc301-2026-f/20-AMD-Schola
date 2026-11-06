# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends SceneTree
## CLI entry point. Exported apps run the same suite with -- --smoke-test.

const SmokeSuite := preload("res://tests/d3_smoke_suite.gd")


func _initialize() -> void:
	root.add_child.call_deferred(SmokeSuite.new())
