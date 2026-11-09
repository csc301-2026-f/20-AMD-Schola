// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/environment/schola_agent.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <memory>
#include <vector>

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
 *   2. ScholaAgent::_observe, then _get_step_result run for each of those
 *      agents, in the same call.
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
	 * Override in GDScript: return this agent's result after _observe().
	 *
	 * Required hook, called once per acting agent per step. Returns a Dictionary:
	 * - reward: required finite int or float representable as a core float.
	 * - terminated: bool, default false; a natural episode ending.
	 * - truncated: bool, default false; a user-defined external cutoff.
	 * - info: Dictionary of String/StringName keys and values, default empty.
	 * Unknown fields and invalid types are errors. Both flags may be true.
	 * Implement any desired step limit by returning truncated = true. During this
	 * hook, get_episode_step() counts completed steps, so the current step is +1.
	 * Reset stays separate and does not invoke this hook or award a reward.
	 *
	 * @param agent The agent whose observation was just collected.
	 * @return A result Dictionary. Variant return allows validation of wrong types
	 *         without Godot silently coercing the result to a Dictionary.
	 */
	GDVIRTUAL1R(godot::Variant, _get_step_result, ScholaAgent *)

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

	/** Optional definition templates for every possible training ID, including future spawns.
	 * Defaults to the current descendants. Templates are not owned or activated.
	 */
	GDVIRTUAL0RC(godot::TypedArray<ScholaAgent>, _get_possible_agents)
	godot::TypedArray<ScholaAgent> get_possible_agents() const;

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
	 * Reports missing agents, duplicate resolved IDs, and each agent's resource
	 * configuration errors. Script hooks are checked separately by editor warnings.
	 *
	 * @return One message per problem; empty when the configuration is valid.
	 */
	godot::PackedStringArray get_configuration_errors() const;

	/**
	 * Godot hook that shows a warning icon on the node in the editor.
	 *
	 * @return Configuration errors and missing required behavior hooks.
	 */
	godot::PackedStringArray _get_configuration_warnings() const override;

protected:
	static void _bind_methods();
	void _notification(int p_what);

private:
	friend class ScholaAgent;

	godot::PackedStringArray collect_configuration_diagnostics(bool p_include_hooks) const;
	void on_script_changed();
	void queue_configuration_refresh();
	void refresh_configuration_warnings();
	std::vector<godot::Ref<godot::Script>> watched_scripts;
	bool configuration_refresh_queued = false;

	// === US1 Addition Below ===

	// Created with the node so get_rng() is never null.
	godot::Ref<godot::RandomNumberGenerator> rng;

	// The adapter behind get_environment(), created on the first call.
	std::unique_ptr<GodotEnvironmentAdapter> environment_adapter;

	// === End US1 Addition ===
};
