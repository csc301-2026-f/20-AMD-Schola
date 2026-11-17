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
	 * Returns the agent's spaces and agent_type.
	 *
	 * The first successful call resolves the spaces: from _define_spaces() if
	 * the script has it, otherwise from the Inspector. Later calls return that
	 * same saved copy, so training, inference and every step agree on one
	 * definition. A failed call saves nothing and can be retried.
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
	// Fills the saved spaces once; does nothing after the first success.
	schola::Status resolve_spaces();

	ScholaAgent *node = nullptr; // Not owned.

	// Saved by the first successful define() and kept for this node's
	// lifetime. They are plain values, not resources, so editing a resource
	// later cannot change them. observe() and act() read them every step.
	schola::Space observation_space;
	schola::Space action_space;
	bool defined = false;
	// True while _define_spaces() runs, to stop it from re-entering define().
	bool resolving = false;
};
