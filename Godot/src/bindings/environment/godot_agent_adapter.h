// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/environment/agent.h"
#include "core/spaces/space.h"

class ScholaAgent;

/**
 * Lets core code use a ScholaAgent node as a schola::Agent.
 *
 * Core calls define(), observe() and act(). This class answers each one by
 * calling the developer's GDScript hook and converting between Godot
 * Variants and core Points, so core never has to know Godot exists.
 *
 * Training reaches it through the environment adapter. Local inference in a
 * shipped game uses it directly, with no environment at all.
 *
 * The ScholaAgent node creates and owns this adapter, so the node always
 * outlives it. Main thread only. Every failure names the agent and leaves
 * the output untouched.
 */
class GodotAgentAdapter final : public schola::Agent {
public:
	// p_node is not owned.
	explicit GodotAgentAdapter(ScholaAgent *p_node);

	/**
	 * Reads the node's Inspector spaces and agent_type.
	 *
	 * Fails with FAILED_PRECONDITION if either space is unset, or with the
	 * space's own error if its definition is invalid. Safe to call more than
	 * once, since training and inference may both define the same agent;
	 * each call refreshes the cached spaces.
	 */
	schola::Status define(schola::InteractionDefinition &r_definition) override;

	/**
	 * Calls _observe() and converts its result into a Point.
	 *
	 * Fails with FAILED_PRECONDITION before define() or if _observe() is not
	 * overridden, and with INVALID_ARGUMENT if the value does not fit the
	 * observation space.
	 */
	schola::Status observe(schola::Point &r_observation) override;

	/**
	 * Checks the action against the action space, then passes it to _act().
	 *
	 * A rejected action never reaches _act(), so the agent does not move.
	 * Fails with FAILED_PRECONDITION before define() or if _act() is not
	 * overridden.
	 */
	schola::Status act(const schola::Point &p_action) override;

private:
	ScholaAgent *node = nullptr; // Not owned.

	// Cached by define(): observe() needs the shape to convert into, and
	// act() needs it to reject a bad action.
	schola::Space observation_space;
	schola::Space action_space;
	bool defined = false;
};
