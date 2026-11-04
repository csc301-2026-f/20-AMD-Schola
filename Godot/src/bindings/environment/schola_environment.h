// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/environment/schola_agent.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <memory>

namespace schola {
class Environment;
} // namespace schola

class GodotEnvironmentAdapter;

/**
 * Godot-facing config node for one trainable environment.
 *
 * Gameplay behaviour comes from the GDScript hooks below (US1), and the
 * training lifecycle drives it through get_environment() (US4). The
 * ScholaAgent nodes below this node are its agents.
 *
 * Each step runs in this order:
 *   1. ScholaAgent::_act runs for every agent still in the episode.
 *   2. ScholaAgent::_observe, then _get_reward, _is_terminated, _is_truncated
 *      and _get_info run for each of those agents, in the same call.
 *   3. Godot runs physics afterwards, so an action's effect may first appear
 *      in the next step's observation.
 *
 * Signals, registered in _bind_methods():
 * - episode_started: after _reset_episode, once observations are readable.
 * - episode_ended: once every agent has terminated or truncated.
 */
class ScholaEnvironment : public godot::Node {
	GDCLASS(ScholaEnvironment, godot::Node)

public:
	/** Creates the node and its RNG, so get_rng() is never null. */
	ScholaEnvironment();

	/** Defined in the .cpp, where GodotEnvironmentAdapter is a complete type. */
	~ScholaEnvironment() override;

	/**
	 * Sets the episode step limit.
	 *
	 * @param p_max_episode_steps 0 for no step limit; a positive value
	 *        truncates unfinished agents when an episode reaches that many
	 *        steps. A negative value is a configuration error.
	 */
	void set_max_episode_steps(int32_t p_max_episode_steps);

	/**
	 * @return The episode step limit; 0 means no step limit.
	 */
	int32_t get_max_episode_steps() const;

	// === US1 Additions Below ===

	/**
	 * Override in GDScript: return the scene to a start state.
	 *
	 * Called once per reset. When seed is an int, seed get_rng() with it and
	 * draw all episode randomness from there; that is what makes a run
	 * reproducible. Optional: leaving it out resets nothing.
	 *
	 * @param seed An int when a seed was supplied, and null otherwise.
	 * @param options Free-form reset settings as a Dictionary.
	 */
	GDVIRTUAL2(_reset_episode, godot::Variant, godot::Dictionary)

	/**
	 * Override in GDScript: reward for the step that just finished.
	 *
	 * Called once per agent each step, following _observe().
	 *
	 * @param agent The agent this reward is for.
	 * @return A reward value. No default; every environment must override
	 *         this.
	 */
	GDVIRTUAL1R(double, _get_reward, ScholaAgent *)

	/**
	 * Override in GDScript: did this agent reach a real end state?
	 *
	 * Called once per agent, same timing as _get_reward.
	 *
	 * @param agent The agent in question.
	 * @return true if the episode ended on its own terms for this agent.
	 *         Defaults to false if left unoverridden.
	 */
	GDVIRTUAL1R(bool, _is_terminated, ScholaAgent *)

	/**
	 * Override in GDScript: was this agent cut off early?
	 *
	 * Called once per agent, same timing as _get_reward.
	 *
	 * @param agent The agent in question.
	 * @return true if the episode was cut off externally for this agent.
	 *         Defaults to false if left unoverridden.
	 */
	GDVIRTUAL1R(bool, _is_truncated, ScholaAgent *)

	/**
	 * Override in GDScript: optional extra data passed through to Python.
	 *
	 * Called once per agent, same timing as _get_reward.
	 *
	 * @param agent The agent in question.
	 * @return A Dictionary of String keys and String values. Defaults to an
	 *         empty Dictionary if left unoverridden.
	 */
	GDVIRTUAL1R(godot::Dictionary, _get_info, ScholaAgent *)

	/**
	 * @return Steps completed since the last reset. During a step's hooks,
	 *         the current step is not counted yet. 0 before the first reset.
	 */
	int64_t get_episode_step() const;

	/**
	 * This environment's random source.
	 *
	 * Use it for every episode-level random choice; anything drawn from
	 * elsewhere ignores the seed and makes runs unreproducible.
	 *
	 * @return The same RandomNumberGenerator on every call; never null.
	 */
	godot::Ref<godot::RandomNumberGenerator> get_rng() const;

	// === End US1 Additions ===

	/**
	 * Finds this environment's agents.
	 *
	 * Separate environment nodes in one scene are valid. A nested
	 * ScholaEnvironment is not searched, so its agents are never counted
	 * twice.
	 *
	 * @return The ScholaAgent descendants of this node, in scene-tree order.
	 */
	godot::TypedArray<ScholaAgent> get_agents() const;

	/**
	 * The US1 core adapter for this node.
	 *
	 * ScholaEnvironment is the Godot wrapper; schola::Environment is the
	 * engine-independent abstraction owned by US1. The adapter is created on
	 * the first call and owned by this node.
	 *
	 * @return A non-owning pointer that stays valid for as long as this node
	 *         exists, or null while the node is outside the scene tree.
	 */
	schola::Environment *get_environment();

	/** Read-only version of get_environment(); returns the same adapter. */
	const schola::Environment *get_environment() const;

	/**
	 * Checks the Inspector and scene-tree configuration.
	 *
	 * Reports a negative max_episode_steps, a missing ScholaAgent, and every
	 * agent's own configuration errors, prefixed with its agent ID. Duplicate
	 * agent IDs are reported by the adapter's initialize() instead.
	 *
	 * @return One message per problem; empty when the configuration is valid.
	 */
	godot::PackedStringArray get_configuration_errors() const;

	/**
	 * Godot hook that shows a warning icon on the node in the editor.
	 *
	 * @return The same messages as get_configuration_errors().
	 */
	godot::PackedStringArray _get_configuration_warnings() const override;

protected:
	static void _bind_methods();

private:
	int32_t max_episode_steps = 0;

	// === US1 Addition Below ===

	// Created with the node so get_rng() is never null.
	godot::Ref<godot::RandomNumberGenerator> rng;

	// The adapter behind get_environment(), created on the first call.
	std::unique_ptr<GodotEnvironmentAdapter> environment_adapter;

	// === End US1 Addition ===
};
