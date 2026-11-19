# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

extends GdUnitTestSuite

const Example := preload("res://examples/manual_environment/main.tscn")


class FaultyAgent extends "res://examples/manual_environment/agent.gd":
	func _observe() -> Variant:
		return 99


var _previous_scene: Node
var _example: Node


func before_test() -> void:
	_previous_scene = get_tree().current_scene
	_example = auto_free(Example.instantiate())
	get_tree().root.add_child(_example)
	get_tree().current_scene = _example
	await get_tree().process_frame


func after_test() -> void:
	get_tree().current_scene = _previous_scene


func test_manual_actions_complete_episode_and_reset() -> void:
	assert_int(_example.last_result["status"]["code"]).is_equal(0)
	assert_int(_example.last_result["value"][0]["walker"]["observation"]).is_equal(0)
	var result: Dictionary
	for index in range(4):
		result = _example.submit_action(1)
		assert_int(result["status"]["code"]).is_equal(0)
	var state: Dictionary = result["value"]["state"][0]["walker"]
	assert_int(state["observation"]).is_equal(4)
	assert_float(state["reward"]).is_equal(1.0)
	assert_bool(state["terminated"]).is_true()
	assert_bool(state["truncated"]).is_false()
	assert_dict(state["info"]).is_equal({"goal": "4", "step": "4"})
	assert_bool(_example.episode_done).is_true()
	assert_int(_example.monitor.step).is_equal(4)
	assert_float(_example.monitor.episode_return).is_equal_approx(0.97, 0.00001)
	assert_bool(_example.monitor.is_episode_active()).is_false()
	var retained: Dictionary = _example.submit_action(0)
	assert_int(retained["value"]["state"][0]["walker"]["observation"]).is_equal(4)
	assert_int(_example.monitor.step).is_equal(4)
	var reset: Dictionary = _example.reset_episode()
	assert_int(reset["status"]["code"]).is_equal(0)
	assert_int(reset["value"][0]["walker"]["observation"]).is_equal(0)
	assert_bool(_example.episode_done).is_false()
	assert_int(_example.monitor.episode).is_equal(2)
	assert_int(_example.monitor.step).is_equal(0)
	assert_float(_example.monitor.episode_return).is_equal(0.0)
	assert_bool(_example.monitor.is_episode_active()).is_true()
	result = _example.submit_action(1)
	assert_int(result["value"]["state"][0]["walker"]["observation"]).is_equal(1)


func test_step_limit_truncates_without_reaching_goal() -> void:
	var result: Dictionary
	for index in range(8):
		result = _example.submit_action(0)
	var state: Dictionary = result["value"]["state"][0]["walker"]
	assert_int(state["observation"]).is_equal(0)
	assert_bool(state["terminated"]).is_false()
	assert_bool(state["truncated"]).is_true()
	assert_bool(_example.episode_done).is_true()
	assert_int(_example.monitor.step).is_equal(8)
	assert_bool(_example.monitor.is_episode_active()).is_false()


func test_seeded_reset_repeats_start_and_forwards_options() -> void:
	var first: Dictionary = _example.reset_episode(42, {"start": "random"})
	_example.submit_action(1)
	var second: Dictionary = _example.reset_episode(42, {"start": "random"})
	assert_dict(second["value"]).is_equal(first["value"])
	assert_int(_example.get_node("Environment").last_seed).is_equal(42)
	assert_dict(_example.get_node("Environment").last_options).is_equal({"start": "random"})


func test_invalid_action_reports_structured_error_without_advancing() -> void:
	var invalid: Dictionary = _example.submit_action("not an action")
	assert_int(invalid["status"]["code"]).is_not_equal(0)
	assert_str(invalid["status"]["message"]).is_not_empty()
	assert_object(invalid["value"]).is_null()
	assert_int(_example.get_node("Environment").get_episode_step()).is_equal(0)
	assert_int(_example.monitor.step).is_equal(0)
	assert_float(_example.monitor.episode_return).is_equal(0.0)
	assert_bool(_example.episode_done).is_false()
	assert_bool(_example.monitor.is_episode_active()).is_true()
	for button in _example._action_buttons:
		assert_bool(button.disabled).is_false()
	var valid: Dictionary = _example.submit_action(1)
	assert_int(valid["status"]["code"]).is_equal(0)
	assert_int(valid["value"]["state"][0]["walker"]["observation"]).is_equal(1)
	assert_bool(_example._reset_button.disabled).is_false()


func test_invalid_observation_stops_episode_and_disables_controls() -> void:
	_example.get_node("Environment/Agent").set_script(FaultyAgent)
	var result: Dictionary = _example.submit_action(1)
	assert_int(result["status"]["code"]).is_not_equal(0)
	assert_bool(_example.host.is_session_active()).is_false()
	assert_str(_example.monitor._status.text).is_equal("Stopped · session error")
	assert_bool(_example.episode_done).is_true()
	assert_bool(_example.monitor.is_episode_active()).is_false()
	assert_int(_example.monitor.step).is_equal(0)
	assert_float(_example.monitor.episode_return).is_equal(0.0)
	for button in _example._action_buttons:
		assert_bool(button.disabled).is_true()
	assert_str(_example._board.text).contains("Restart")
	assert_bool(_example._reset_button.disabled).is_true()
	var reset: Dictionary = _example.reset_episode()
	assert_dict(reset).is_equal(result)
	var repeated: Dictionary = _example.submit_action(1)
	assert_dict(repeated).is_equal(result)
	assert_str(_example._board.text).contains("Restart")


func test_invalid_reset_observation_stops_episode() -> void:
	_example.get_node("Environment/Agent").set_script(FaultyAgent)
	var result: Dictionary = _example.reset_episode()
	assert_int(result["status"]["code"]).is_not_equal(0)
	assert_bool(_example.episode_done).is_true()
	assert_bool(_example.monitor.is_episode_active()).is_false()
	assert_str(_example.monitor._status.text).is_equal("Stopped · session error")
	assert_bool(_example._reset_button.disabled).is_true()
	for button in _example._action_buttons:
		assert_bool(button.disabled).is_true()
	assert_str(_example._board.text).contains("Restart")


func test_arrow_keys_step_agent_with_toggle_focused_but_preserve_seed_editing() -> void:
	_example._random_start.grab_focus()
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	get_viewport().push_input(right)
	await get_tree().process_frame
	assert_int(_example.monitor.step).is_equal(1)
	assert_int(_example.get_node("Environment/Agent").position).is_equal(1)
	var seed_edit: LineEdit = _example._seed.get_line_edit()
	seed_edit.grab_focus()
	get_viewport().push_input(right)
	await get_tree().process_frame
	assert_int(_example.monitor.step).is_equal(1)
