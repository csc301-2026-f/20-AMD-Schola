# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
extends GdUnitTestSuite

const Monitor = preload("res://addons/schola/ui/schola_monitor.gd")
const Preview = preload("res://examples/ui_preview/main.tscn")


func test_monitor_accumulates_rewards_and_resets() -> void:
	var monitor: ScholaMonitor = auto_free(Monitor.new())
	add_child(monitor)
	monitor.begin_episode(1, PackedStringArray(["A", "B"]), 10)
	monitor.record_step({"A": 1.5, "B": -0.5})
	monitor.record_step({"A": -0.25, "B": 2.0})
	assert_float(monitor.episode_return).is_equal(2.75)
	assert_float(monitor.agent_returns["A"]).is_equal(1.25)
	assert_int(monitor.step).is_equal(2)
	monitor.end_episode(true)
	monitor.record_step({"A": 100.0})
	assert_float(monitor.episode_return).is_equal(2.75)
	assert_bool(monitor.is_episode_active()).is_false()
	assert_str(monitor._status.text).contains("Truncated")
	monitor.begin_episode(2, PackedStringArray(["C"]))
	assert_int(monitor.step).is_equal(0)
	assert_float(monitor.episode_return).is_equal(0.0)
	assert_dict(monitor.agent_returns).contains_keys("C").not_contains_keys("A", "B")
	assert_str(monitor._status.text).contains("Receiving")


func test_monitor_bounds_history_and_handles_empty_episode() -> void:
	var monitor: ScholaMonitor = auto_free(Monitor.new())
	add_child(monitor)
	monitor.history_limit = 8
	monitor.begin_episode(1, PackedStringArray(["A"]))
	for index in range(20):
		monitor.record_step({"A": -1.0})
	assert_int(monitor._history.size()).is_equal(8)
	assert_float(monitor.episode_return).is_equal(-20.0)
	monitor.begin_episode(2, PackedStringArray())
	assert_bool(monitor._empty.visible).is_true()
	monitor.end_episode()
	assert_str(monitor._status.text).contains("Terminated")


func test_preview_controls_drive_only_sample_telemetry() -> void:
	var preview: Control = auto_free(Preview.instantiate())
	add_child(preview)
	preview._next_step()
	assert_int(preview.monitor.step).is_equal(1)
	preview._finish(false)
	preview._next_step()
	assert_int(preview.monitor.step).is_equal(1)
	preview._new_episode()
	assert_int(preview.monitor.episode).is_equal(2)
	for index in range(60):
		preview._next_step()
	assert_int(preview.monitor.step).is_equal(60)
	assert_bool(preview.monitor.is_episode_active()).is_false()
	assert_str(preview.monitor._status.text).contains("Truncated")
