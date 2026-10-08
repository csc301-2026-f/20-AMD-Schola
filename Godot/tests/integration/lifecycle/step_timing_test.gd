# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

class_name StepTimingTest
extends GdUnitTestSuite


func test_physics_action_changes_state_after_physics_step() -> void:
	var body := auto_free(RigidBody2D.new()) as RigidBody2D
	body.gravity_scale = 0.0
	body.lock_rotation = true

	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	body.add_child(collision)
	add_child(body)

	# Allow the body to enter the physics world.
	await get_tree().physics_frame

	var position_before_action := body.position

	body.apply_central_impulse(Vector2(100.0, 0.0))
	var position_immediately_after_action := body.position

	assert_vector(position_immediately_after_action).is_equal(
		position_before_action
	)

	# The physics engine integrates the impulse between these signals.
	await get_tree().physics_frame

	var position_after_physics := body.position

	assert_float(position_after_physics.x).is_greater(
		position_before_action.x
	)
