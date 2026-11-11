// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/godot_environment_adapter.h"

#include "bindings/environment/schola_agent.h"
#include "bindings/environment/schola_environment.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <set>
#include <string>
#include <utility>

namespace {

std::string to_std_string(const godot::String &p_string) {
	return p_string.utf8().get_data();
}

// queue_free() on a container does not mark its children as queued yet.
bool is_live_member(const ScholaEnvironment *p_environment, const ScholaAgent *p_agent) {
	bool member = false;
	for (const godot::Node *ancestor = p_agent; ancestor != nullptr; ancestor = ancestor->get_parent()) {
		if (ancestor->is_queued_for_deletion()) {
			return false;
		}
		member = member || ancestor == p_environment;
	}
	return member;
}

// Prefixes every message with the environment node's name so failures say
// which environment broke.
schola::Status environment_error(const ScholaEnvironment *p_node, schola::StatusCode p_code, const std::string &p_message) {
	const std::string name = to_std_string(godot::String(p_node->get_name()));
	return schola::Status::error(p_code, "Environment '" + name + "': " + p_message);
}

// Same prefix GodotAgentAdapter uses, so every agent failure reads alike.
schola::Status agent_error(const schola::AgentId &p_id, schola::StatusCode p_code, const std::string &p_message) {
	return schola::Status::error(p_code, "Agent '" + p_id + "': " + p_message);
}

// Looks an agent node up by its Godot instance ID. ObjectDB returns null once
// Godot has freed the node, so this never hands back a dangling pointer.
schola::Status find_agent_node(const schola::AgentId &p_id, godot::ObjectID p_node_id, ScholaAgent *&r_node) {
	godot::Object *object = godot::ObjectDB::get_instance(static_cast<uint64_t>(p_node_id));
	ScholaAgent *agent_node = godot::Object::cast_to<ScholaAgent>(object);
	if (agent_node == nullptr) {
		return agent_error(p_id, schola::StatusCode::FAILED_PRECONDITION, "the agent node was freed");
	}
	r_node = agent_node;
	return schola::Status::ok();
}

// Reset options arrive as std::strings; _reset_episode() takes a Dictionary.
godot::Dictionary to_dictionary(const std::map<std::string, std::string> &p_options) {
	godot::Dictionary dictionary;
	for (const auto &[key, value] : p_options) {
		dictionary[godot::String::utf8(key.c_str())] = godot::String::utf8(value.c_str());
	}
	return dictionary;
}

bool is_text(const godot::Variant &p_value) {
	return p_value.get_type() == godot::Variant::STRING || p_value.get_type() == godot::Variant::STRING_NAME;
}

// Result info must contain String keys and String values, because Python
// receives info as a map of strings. Anything else is rejected rather than
// silently stringified.
schola::Status to_info(const godot::Dictionary &p_dictionary, std::map<std::string, std::string> &r_info) {
	std::map<std::string, std::string> info;
	const godot::Array keys = p_dictionary.keys();
	for (int32_t index = 0; index < keys.size(); ++index) {
		const godot::Variant key = keys[index];
		const godot::Variant value = p_dictionary.get(key, godot::Variant());
		if (!is_text(key) || !is_text(value)) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "info keys and values must be Strings");
		}
		info[to_std_string(godot::String(key))] = to_std_string(godot::String(value));
	}
	r_info = std::move(info);
	return schola::Status::ok();
}

// Parse without coercion or partial writes. Observation is collected separately
// through _observe(); this callback supplies only the episode result fields.
schola::Status to_step_result(const godot::Variant &p_value, schola::AgentState &r_state) {
	using godot::Variant;
	if (p_value.get_type() != Variant::DICTIONARY) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "expected a Dictionary");
	}
	const godot::Dictionary result = p_value;
	const godot::Array keys = result.keys();
	for (int32_t index = 0; index < keys.size(); ++index) {
		const Variant key = keys[index];
		if (!is_text(key)) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "field names must be Strings");
		}
		const godot::String name = key;
		if (name != "reward" && name != "terminated" && name != "truncated" && name != "info") {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "unknown field '" + to_std_string(name) + "'");
		}
	}
	const Variant reward = result.get("reward", Variant());
	if (reward.get_type() != Variant::INT && reward.get_type() != Variant::FLOAT) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "reward is required and must be an int or float");
	}
	const double reward_value = reward;
	if (!std::isfinite(reward_value) || std::abs(reward_value) > std::numeric_limits<float>::max()) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "reward must be finite and fit in a float32");
	}
	const Variant terminated = result.get("terminated", false);
	const Variant truncated = result.get("truncated", false);
	if (terminated.get_type() != Variant::BOOL || truncated.get_type() != Variant::BOOL) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "terminated and truncated must be bools");
	}
	const Variant info = result.get("info", godot::Dictionary());
	if (info.get_type() != Variant::DICTIONARY) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "info must be a Dictionary");
	}
	std::map<std::string, std::string> converted_info;
	const schola::Status status = to_info(info, converted_info);
	if (!status.is_ok()) {
		return status;
	}
	r_state.reward = static_cast<float>(reward_value);
	r_state.terminated = terminated;
	r_state.truncated = truncated;
	r_state.info = std::move(converted_info);
	return schola::Status::ok();
}

} // namespace

GodotEnvironmentAdapter::GodotEnvironmentAdapter(ScholaEnvironment *p_node) :
		node(p_node) {}

schola::Status GodotEnvironmentAdapter::initialize(std::map<schola::AgentId, schola::InteractionDefinition> &r_agents) {
	// Possible definitions are captured once; live nodes are rediscovered every operation.
	if (initialized) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "initialize() was already called");
	}

	// The node already knows how to spot a broken scene (no agents, missing
	// spaces, and so on), so reuse its checks instead of repeating them.
	const godot::PackedStringArray errors = node->get_configuration_errors();
	if (!errors.is_empty()) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, to_std_string(godot::String("; ").join(errors)));
	}

	const godot::TypedArray<ScholaAgent> agent_nodes = node->get_possible_agents();
	if (agent_nodes.is_empty()) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "add a ScholaAgent node below this environment");
	}

	// Build everything in local variables first, so a failure part way
	// through leaves this adapter and the caller's map untouched.
	std::map<schola::AgentId, schola::InteractionDefinition> definitions;
	for (int32_t index = 0; index < agent_nodes.size(); ++index) {
		godot::Object *agent_object = agent_nodes[index];
		ScholaAgent *agent_node = godot::Object::cast_to<ScholaAgent>(agent_object);
		if (agent_node == nullptr) {
			continue;
		}

		// Two agents with the same ID would overwrite each other in every map
		// Python sees, so refuse the whole environment.
		const schola::AgentId id = to_std_string(agent_node->get_resolved_agent_id());
		if (definitions.count(id) != 0) {
			return agent_error(id, schola::StatusCode::FAILED_PRECONDITION, "agent_id is used by more than one agent");
		}

		// Each agent reads its own Inspector spaces. Its error already names
		// the agent, so pass it straight through.
		schola::InteractionDefinition definition;
		const schola::Status status = agent_node->get_agent()->define(definition);
		if (!status.is_ok()) {
			return status;
		}

		definitions.emplace(id, std::move(definition));
	}

	// Everything passed. Commit, then hand the definitions to the caller.
	this->definitions = definitions;
	initialized = true;
	r_agents = std::move(definitions);
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::collect_current_agents(std::vector<AgentEntry> &r_agents) const {
	std::set<schola::AgentId> seen;
	const auto nodes = node->get_agents();
	for (int32_t i = 0; i < nodes.size(); ++i) {
		godot::Object *object = nodes[i];
		auto *agent = godot::Object::cast_to<ScholaAgent>(object);
		if (agent == nullptr || !is_live_member(node, agent)) {
			continue;
		}
		const auto id = to_std_string(agent->get_resolved_agent_id());
		const auto previous_node = episode_nodes.find(id);
		if (previous_node != episode_nodes.end() && previous_node->second != godot::ObjectID(agent->get_instance_id())) {
			return agent_error(id, schola::StatusCode::INVALID_DATA, "agent node was replaced before reset; use a new declared ID");
		}
		const auto declared = definitions.find(id);
		if (declared == definitions.end() || !seen.insert(id).second) {
			return agent_error(id, schola::StatusCode::INVALID_DATA, "agent ID must be declared and unique");
		}
		schola::InteractionDefinition definition;
		auto status = agent->get_agent()->define(definition);
		if (!status.is_ok()) {
			return status;
		}
		if (definition.observation_space != declared->second.observation_space ||
				definition.action_space != declared->second.action_space || definition.agent_type != declared->second.agent_type) {
			return agent_error(id, schola::StatusCode::INCOMPATIBLE, "spawned agent differs from its declared definition");
		}
		r_agents.push_back({ id, godot::ObjectID(agent->get_instance_id()) });
	}
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::reset(const schola::ResetSettings &p_settings,
		std::map<schola::AgentId, schola::InitialAgentState> &r_states) {
	if (!initialized) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "reset() called before initialize()");
	}

	// Whatever happens below, the previous episode is over. If this reset
	// fails, step() must refuse to run until a reset succeeds.
	episode_active = false;

	// Seed the environment's RNG only when Python sent a seed. Without one,
	// the RNG keeps running from where it was, as ResetSettings describes.
	if (p_settings.seed.has_value()) {
		const godot::Ref<godot::RandomNumberGenerator> rng = node->get_rng();
		if (rng.is_null()) {
			return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "get_rng() returned null, so the seed cannot be applied");
		}
		rng->set_seed(static_cast<uint64_t>(*p_settings.seed));
	}

	// _reset_episode() gets the seed as an int, or null when there is none,
	// so the script can tell the two apart. Overriding it is optional: a
	// scene with nothing to put back can leave it out.
	const godot::Variant seed = p_settings.seed.has_value() ? godot::Variant(static_cast<int64_t>(*p_settings.seed)) : godot::Variant();
	GDVIRTUAL_CALL_PTR(node, _reset_episode, seed, to_dictionary(p_settings.options));

	episode_nodes.clear();
	std::vector<AgentEntry> current;
	auto collect_status = collect_current_agents(current);
	if (!collect_status.is_ok()) {
		return collect_status;
	}
	last_states.clear();

	// Read every active agent's first observation of the fresh episode.
	std::map<schola::AgentId, schola::InitialAgentState> states;
	for (const AgentEntry &entry : current) {
		ScholaAgent *agent_node = nullptr;
		schola::Status status = find_agent_node(entry.id, entry.node_id, agent_node);
		if (!status.is_ok()) {
			return status;
		}
		if (!is_live_member(node, agent_node)) {
			continue;
		}

		schola::InitialAgentState state;
		status = agent_node->get_agent()->observe(state.observation);
		if (!status.is_ok()) {
			return status;
		}
		status = find_agent_node(entry.id, entry.node_id, agent_node);
		if (!status.is_ok() || !is_live_member(node, agent_node)) {
			continue;
		}
		last_states.emplace(entry.id, schola::AgentState{ state.observation, 0.0f, false, false, state.info });
		episode_nodes.emplace(entry.id, entry.node_id);
		states.emplace(entry.id, std::move(state));
	}

	episode_active = true;
	episode_step = 0;
	r_states = std::move(states);
	node->emit_signal("episode_started");
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::step(const std::map<schola::AgentId, schola::Point> &p_actions,
		std::map<schola::AgentId, schola::AgentState> &r_states) {
	if (!initialized || !episode_active) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "step() called before reset()");
	}

	std::vector<AgentEntry> current;
	auto status = collect_current_agents(current);
	if (!status.is_ok()) {
		return status;
	}
	// Validate the full request before invoking any gameplay hooks.
	size_t active_count = 0;
	for (const auto &[id, previous] : last_states) {
		if (!previous.terminated && !previous.truncated) {
			++active_count;
			const auto action = p_actions.find(id);
			if (action == p_actions.end()) {
				return agent_error(id, schola::StatusCode::INVALID_ARGUMENT, "missing action");
			}
			status = definitions.at(id).action_space.validate(action->second);
			if (!status.is_ok()) {
				return agent_error(id, status.get_code(), "rejected action: " + status.get_message());
			}
		}
	}
	if (p_actions.size() != active_count) {
		return environment_error(node, schola::StatusCode::INVALID_ARGUMENT, "actions must name exactly the active agents");
	}

	// A missing _get_step_result() would otherwise only show up after every agent
	// had already acted, so catch it here while the world is still untouched.
	if (!p_actions.empty() && !GDVIRTUAL_IS_OVERRIDDEN_PTR(node, _get_step_result)) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "_get_step_result() is not overridden");
	}
	for (const auto &entry : current) {
		const auto action = p_actions.find(entry.id);
		if (action == p_actions.end()) {
			continue;
		}
		ScholaAgent *agent = nullptr;
		status = find_agent_node(entry.id, entry.node_id, agent);
		// Another agent may have removed this one during its action.
		if (!status.is_ok() || !is_live_member(node, agent)) {
			continue;
		}
		status = agent->get_agent()->act(action->second);
		if (!status.is_ok()) {
			return status;
		}
	}
	current.clear();
	status = collect_current_agents(current);
	if (!status.is_ok()) {
		return status;
	}
	std::map<schola::AgentId, schola::AgentState> states;
	std::set<schola::AgentId> observed_ids;
	std::vector<AgentEntry> final_agents;
	while (true) {
		for (const auto &entry : current) {
			if (!observed_ids.insert(entry.id).second) {
				continue;
			}
			const auto previous = last_states.find(entry.id);
			if (previous != last_states.end() && (previous->second.terminated || previous->second.truncated)) {
				continue; // An ID is retired until the next environment reset.
			}
			ScholaAgent *agent = nullptr;
			status = find_agent_node(entry.id, entry.node_id, agent);
			if (!status.is_ok() || !is_live_member(node, agent)) {
				continue;
			}
			schola::AgentState state;
			episode_nodes.emplace(entry.id, entry.node_id);
			status = agent->get_agent()->observe(state.observation);
			if (!status.is_ok()) {
				return status;
			}
			// Observation is gameplay code: it can free, queue, or detach this node.
			status = find_agent_node(entry.id, entry.node_id, agent);
			if (!status.is_ok() || !is_live_member(node, agent)) {
				if (previous == last_states.end()) {
					state.terminated = true;
					states.emplace(entry.id, std::move(state));
				}
				continue;
			}
			if (previous != last_states.end()) {
				godot::Variant result;
				if (!GDVIRTUAL_CALL_PTR(node, _get_step_result, agent, result)) {
					return agent_error(entry.id, schola::StatusCode::FAILED_PRECONDITION, "_get_step_result() could not be called");
				}
				status = to_step_result(result, state);
				if (!status.is_ok()) {
					return agent_error(entry.id, status.get_code(), "_get_step_result(): " + status.get_message());
				}
			}
			states.emplace(entry.id, std::move(state));
		}
		// Observation and result callbacks may spawn more declared agents. Observe
		// each ID at most once, including births discovered by these later scans.
		final_agents.clear();
		status = collect_current_agents(final_agents);
		if (!status.is_ok()) {
			return status;
		}
		bool found_birth = false;
		for (const auto &entry : final_agents) {
			if (observed_ids.count(entry.id) == 0) {
				current.push_back(entry);
				found_birth = true;
			}
		}
		if (!found_birth) {
			break;
		}
	}
	// Reconcile departures only after every callback, including birth observations.
	for (const auto &entry : current) {
		auto result = states.find(entry.id);
		if (result == states.end() || result->second.terminated || result->second.truncated) {
			continue;
		}
		const bool departed = std::none_of(final_agents.begin(), final_agents.end(), [&](const auto &live) {
			return live.id == entry.id && live.node_id == entry.node_id;
		});
		if (departed) {
			const auto previous = last_states.find(entry.id);
			if (previous != last_states.end()) {
				result->second = previous->second;
			}
			result->second.reward = 0.0f;
			result->second.terminated = true;
		}
	}
	for (const auto &[id, previous] : last_states) {
		if (!previous.terminated && !previous.truncated && states.count(id) == 0) {
			auto terminal = previous;
			terminal.reward = 0.0f;
			terminal.terminated = true;
			states.emplace(id, std::move(terminal));
		}
	}
	for (const auto &[id, state] : states) {
		last_states[id] = state;
	}
	for (const auto &entry : current) {
		if (states.count(entry.id) != 0) {
			episode_nodes.emplace(entry.id, entry.node_id);
		}
	}
	++episode_step;
	r_states = std::move(states);
	const bool all_finished = !last_states.empty() && std::all_of(last_states.begin(), last_states.end(), [](const auto &entry) {
		return entry.second.terminated || entry.second.truncated;
	});
	if (all_finished) {
		episode_active = false;
		node->emit_signal("episode_ended");
	}
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::get_agents(std::vector<schola::Agent *> &r_agents) const {
	if (!initialized) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "get_agents() called before initialize()");
	}

	// Build the list locally, so a freed agent leaves the caller's vector
	// untouched.
	std::vector<schola::Agent *> result;
	std::vector<AgentEntry> current;
	auto collected = collect_current_agents(current);
	if (!collected.is_ok()) {
		return collected;
	}
	for (const AgentEntry &entry : current) {
		ScholaAgent *agent_node = nullptr;
		const schola::Status status = find_agent_node(entry.id, entry.node_id, agent_node);
		if (!status.is_ok()) {
			return status;
		}
		result.push_back(agent_node->get_agent());
	}

	r_agents = std::move(result);
	return schola::Status::ok();
}

int64_t GodotEnvironmentAdapter::get_episode_step() const {
	return episode_step;
}
