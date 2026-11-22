// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/adapters/observation_adapter.h"
#include "core/environment/agent.h"
#include "core/spaces/space.h"
#include <godot_cpp/core/object_id.hpp>

#include <memory>
#include <vector>

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
	 * The first successful call works out the spaces: from _define_spaces()
	 * if the script has it, otherwise from Inspector fields or components. Later calls
	 * return that same saved copy, so training, inference and every step
	 * agree on one definition. A failed call saves nothing and can be retried
	 * once the problem is fixed. To use different explicit or callback spaces,
	 * recreate the scene. Component-authored sides can be explicitly redefined
	 * when a new environment initializes the agent, preserving US8's boundary.
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

	void reset_observation_history() override;

private:
	// Saves authored spaces and adapters; explicitly redefines composed sides when needed.
	schola::Status resolve_spaces();

	std::vector<std::unique_ptr<schola::ObservationAdapter>> observation_adapters;
	ScholaAgent *node = nullptr; // Not owned.

	// The saved spaces. They are plain values copied out of the resources,
	// so editing a resource later can't change them. observe() and act()
	// use them every step to convert and check data.
	schola::Space observation_space;
	schola::Space adapted_observation_space;
	schola::Space action_space;
	// True once the spaces above are saved.
	bool defined = false;
	// True while _define_spaces() is running, so it can't loop back into define().
	bool resolving = false;
	std::vector<godot::ObjectID> sensors;
	std::vector<godot::ObjectID> actuators;
	uint64_t validated_revision = 0;
	// Dict resources expose mutable Dictionaries whose in-place edits emit no signal.
	bool mutable_dictionary_spaces = false;
	schola::Status check_components();
	schola::Status check_runtime_components() const;
};
