// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "training/bindings/host_training_backend.h"

#include "core/spaces/point.h"
#include "core/spaces/space.h"
#include "interop/space_dictionary.h"
#include "interop/variant_conversion.h"

#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <map>
#include <string>
#include <utility>

namespace schola {

namespace {

using godot::Variant;

std::string to_std_string(const Variant &p_value) {
	return godot::String(p_value).utf8().get_data();
}

godot::String to_godot_string(const std::string &p_value) {
	return godot::String::utf8(p_value.c_str());
}

bool is_text(const Variant &p_value) {
	return p_value.get_type() == Variant::STRING || p_value.get_type() == Variant::STRING_NAME;
}

// The host and this backend ship together, so a malformed reply is a bug or a
// version mismatch rather than a problem in the developer's scene.
Status bad_reply(const char *p_method, const std::string &p_message) {
	return Status::error(StatusCode::INVALID_DATA, std::string("ScholaTrainingHost.") + p_method + "() returned " + p_message);
}

std::string where(int64_t p_environment, const std::string &p_agent) {
	return "agent '" + p_agent + "' in environment " + std::to_string(p_environment);
}

// Every host method returns {status: {code, message}, value}. Hands back the
// value on success, or the host's own error unchanged.
Status read_result(const Variant &p_result, const char *p_method, Variant &r_value) {
	if (p_result.get_type() != Variant::DICTIONARY) {
		return bad_reply(p_method, "no result Dictionary");
	}
	const godot::Dictionary result = p_result;
	const Variant status_value = result.get("status", Variant());
	if (status_value.get_type() != Variant::DICTIONARY) {
		return bad_reply(p_method, "a result without a status Dictionary");
	}
	const godot::Dictionary status = status_value;
	const Variant code_value = status.get("code", Variant());
	const Variant message_value = status.get("message", Variant());
	if (code_value.get_type() != Variant::INT || !is_text(message_value)) {
		return bad_reply(p_method, "a status without an int code and a String message");
	}
	const int64_t code = code_value;
	if (code < 0 || code > static_cast<int64_t>(StatusCode::RUNTIME_FAILURE)) {
		return bad_reply(p_method, "unknown status code " + std::to_string(code));
	}
	if (code != static_cast<int64_t>(StatusCode::OK)) {
		return Status::error(static_cast<StatusCode>(code), to_std_string(message_value));
	}
	r_value = result.get("value", Variant());
	return Status::ok();
}

// Calls one host method and reads its result.
template <typename... Args>
Status call_host(godot::ObjectID p_host_id, const char *p_method, Variant &r_value, const Args &...p_args) {
	godot::Object *host = godot::ObjectDB::get_instance(static_cast<uint64_t>(p_host_id));
	if (host == nullptr) {
		return Status::error(StatusCode::FAILED_PRECONDITION, "The ScholaTrainingHost was freed during the training session.");
	}
	return read_result(host->call(p_method, p_args...), p_method, r_value);
}

Status read_info(const Variant &p_value, const char *p_method, const std::string &p_where,
		std::map<std::string, std::string> &r_info) {
	if (p_value.get_type() != Variant::DICTIONARY) {
		return bad_reply(p_method, "info for " + p_where + " that is not a Dictionary");
	}
	const godot::Dictionary dictionary = p_value;
	const godot::Array keys = dictionary.keys();
	std::map<std::string, std::string> info;
	for (int64_t index = 0; index < keys.size(); ++index) {
		const Variant key = keys[index];
		const Variant value = dictionary[key];
		if (!is_text(key) || !is_text(value)) {
			return bad_reply(p_method, "info for " + p_where + " with a key or value that is not a String");
		}
		info[to_std_string(key)] = to_std_string(value);
	}
	r_info = std::move(info);
	return Status::ok();
}

// Finds an agent's definition, so its observation can be read in its own space.
const InteractionDefinition *find_agent(const TrainingDefinition &p_definition, int64_t p_environment, const AgentId &p_agent) {
	if (p_environment < 0 || p_environment >= static_cast<int64_t>(p_definition.environments.size())) {
		return nullptr;
	}
	const auto &agents = p_definition.environments[static_cast<size_t>(p_environment)].agents;
	const auto agent = agents.find(p_agent);
	return agent == agents.end() ? nullptr : &agent->second;
}

// Reads the {observation, info, ...} entry for one agent.
Status read_observation(const godot::Dictionary &p_entry, const InteractionDefinition &p_agent, const char *p_method,
		const std::string &p_where, Point &r_observation, std::map<std::string, std::string> &r_info) {
	Point observation;
	const Status status = variant_to_point(p_entry.get("observation", Variant()), p_agent.observation_space, observation);
	if (!status.is_ok()) {
		return bad_reply(p_method, "an observation for " + p_where + " that does not fit its space: " + status.get_message());
	}
	std::map<std::string, std::string> info;
	const Status info_status = read_info(p_entry.get("info", godot::Dictionary()), p_method, p_where, info);
	if (!info_status.is_ok()) {
		return info_status;
	}
	r_observation = std::move(observation);
	r_info = std::move(info);
	return Status::ok();
}

// {environment_id: {agent_id: {observation, info}}}, from reset() and from a step's auto-resets.
Status read_initial_state(const Variant &p_value, const TrainingDefinition &p_definition, const char *p_method,
		InitialState &r_state) {
	if (p_value.get_type() != Variant::DICTIONARY) {
		return bad_reply(p_method, "initial states that are not a Dictionary");
	}
	const godot::Dictionary environments = p_value;
	const godot::Array environment_ids = environments.keys();
	InitialState state;
	for (int64_t index = 0; index < environment_ids.size(); ++index) {
		const Variant environment_id = environment_ids[index];
		const Variant agents_value = environments[environment_id];
		if (environment_id.get_type() != Variant::INT || agents_value.get_type() != Variant::DICTIONARY) {
			return bad_reply(p_method, "initial states that are not keyed by environment ID");
		}
		const int64_t environment = environment_id;
		if (environment < 0 || environment >= static_cast<int64_t>(p_definition.environments.size())) {
			return bad_reply(p_method, "an initial state for unknown environment " + std::to_string(environment));
		}
		InitialEnvironmentState &environment_state = state.environments[static_cast<EnvironmentId>(environment)];
		const godot::Dictionary agents = agents_value;
		const godot::Array agent_ids = agents.keys();
		for (int64_t agent_index = 0; agent_index < agent_ids.size(); ++agent_index) {
			const Variant agent_id = agent_ids[agent_index];
			const Variant entry = agents[agent_id];
			if (!is_text(agent_id) || entry.get_type() != Variant::DICTIONARY) {
				return bad_reply(p_method, "an initial state for environment " + std::to_string(environment) + " that is not keyed by agent ID");
			}
			const AgentId id = to_std_string(agent_id);
			const InteractionDefinition *agent = find_agent(p_definition, environment, id);
			if (agent == nullptr) {
				return bad_reply(p_method, "an initial state for unknown " + where(environment, id));
			}
			InitialAgentState &agent_state = environment_state.agents[id];
			const Status status = read_observation(entry, *agent, p_method, where(environment, id), agent_state.observation, agent_state.info);
			if (!status.is_ok()) {
				return status;
			}
		}
	}
	r_state = std::move(state);
	return Status::ok();
}

// {state: [{agent_id: {observation, reward, terminated, truncated, info}}], initial_state: {...}}
Status read_step_result(const Variant &p_value, const TrainingDefinition &p_definition, StepResult &r_result) {
	const char *method = "step";
	if (p_value.get_type() != Variant::DICTIONARY) {
		return bad_reply(method, "a step result that is not a Dictionary");
	}
	const godot::Dictionary value = p_value;
	const Variant states_value = value.get("state", Variant());
	if (states_value.get_type() != Variant::ARRAY) {
		return bad_reply(method, "a step result without a state Array");
	}
	const godot::Array states = states_value;
	if (states.size() != static_cast<int64_t>(p_definition.environments.size())) {
		return bad_reply(method, std::to_string(states.size()) + " environment states for " + std::to_string(p_definition.environments.size()) + " environments");
	}

	StepResult result;
	result.state.environments.resize(p_definition.environments.size());
	for (int64_t environment = 0; environment < states.size(); ++environment) {
		const Variant agents_value = states[environment];
		if (agents_value.get_type() != Variant::DICTIONARY) {
			return bad_reply(method, "a state for environment " + std::to_string(environment) + " that is not a Dictionary");
		}
		const godot::Dictionary agents = agents_value;
		const godot::Array agent_ids = agents.keys();
		for (int64_t agent_index = 0; agent_index < agent_ids.size(); ++agent_index) {
			const Variant agent_id = agent_ids[agent_index];
			const Variant entry_value = agents[agent_id];
			if (!is_text(agent_id) || entry_value.get_type() != Variant::DICTIONARY) {
				return bad_reply(method, "a state for environment " + std::to_string(environment) + " that is not keyed by agent ID");
			}
			const AgentId id = to_std_string(agent_id);
			const InteractionDefinition *agent = find_agent(p_definition, environment, id);
			if (agent == nullptr) {
				return bad_reply(method, "a state for unknown " + where(environment, id));
			}
			const godot::Dictionary entry = entry_value;
			const Variant reward = entry.get("reward", Variant());
			const Variant terminated = entry.get("terminated", Variant());
			const Variant truncated = entry.get("truncated", Variant());
			if ((reward.get_type() != Variant::FLOAT && reward.get_type() != Variant::INT) ||
					terminated.get_type() != Variant::BOOL || truncated.get_type() != Variant::BOOL) {
				return bad_reply(method, "a state for " + where(environment, id) + " without a numeric reward and bool terminated and truncated");
			}
			AgentState &agent_state = result.state.environments[static_cast<size_t>(environment)].agents[id];
			const Status status = read_observation(entry, *agent, method, where(environment, id), agent_state.observation, agent_state.info);
			if (!status.is_ok()) {
				return status;
			}
			agent_state.reward = static_cast<float>(static_cast<double>(reward));
			agent_state.terminated = terminated;
			agent_state.truncated = truncated;
		}
	}

	const Status status = read_initial_state(value.get("initial_state", godot::Dictionary()), p_definition, method, result.initial_state);
	if (!status.is_ok()) {
		return status;
	}
	r_result = std::move(result);
	return Status::ok();
}

// {environments: [{agents: {agent_id: {observation_space, action_space, agent_type}}}]}
Status read_definition(const Variant &p_value, TrainingDefinition &r_definition) {
	const char *method = "define";
	if (p_value.get_type() != Variant::DICTIONARY) {
		return bad_reply(method, "a definition that is not a Dictionary");
	}
	const Variant environments_value = godot::Dictionary(p_value).get("environments", Variant());
	if (environments_value.get_type() != Variant::ARRAY) {
		return bad_reply(method, "a definition without an environments Array");
	}
	const godot::Array environments = environments_value;
	TrainingDefinition definition;
	definition.environments.resize(static_cast<size_t>(environments.size()));
	for (int64_t environment = 0; environment < environments.size(); ++environment) {
		const Variant environment_value = environments[environment];
		const Variant agents_value = environment_value.get_type() == Variant::DICTIONARY
				? godot::Dictionary(environment_value).get("agents", Variant())
				: Variant();
		if (agents_value.get_type() != Variant::DICTIONARY) {
			return bad_reply(method, "environment " + std::to_string(environment) + " without an agents Dictionary");
		}
		const godot::Dictionary agents = agents_value;
		const godot::Array agent_ids = agents.keys();
		for (int64_t agent_index = 0; agent_index < agent_ids.size(); ++agent_index) {
			const Variant agent_id = agent_ids[agent_index];
			const Variant entry_value = agents[agent_id];
			if (!is_text(agent_id) || entry_value.get_type() != Variant::DICTIONARY) {
				return bad_reply(method, "environment " + std::to_string(environment) + " with agents that are not keyed by agent ID");
			}
			const AgentId id = to_std_string(agent_id);
			const godot::Dictionary entry = entry_value;
			InteractionDefinition &agent = definition.environments[static_cast<size_t>(environment)].agents[id];
			Status status = dictionary_to_space(entry.get("observation_space", Variant()), agent.observation_space);
			if (!status.is_ok()) {
				return bad_reply(method, "an invalid observation_space for " + where(environment, id) + ": " + status.get_message());
			}
			status = dictionary_to_space(entry.get("action_space", Variant()), agent.action_space);
			if (!status.is_ok()) {
				return bad_reply(method, "an invalid action_space for " + where(environment, id) + ": " + status.get_message());
			}
			const Variant agent_type = entry.get("agent_type", Variant());
			if (!is_text(agent_type)) {
				return bad_reply(method, "no agent_type String for " + where(environment, id));
			}
			agent.agent_type = to_std_string(agent_type);
		}
	}
	r_definition = std::move(definition);
	return Status::ok();
}

// {environment_id: {seed, options}}, as ScholaTrainingHost.reset() takes it.
godot::Dictionary encode_reset(const ResetRequest &p_request) {
	godot::Dictionary request;
	for (const auto &[environment_id, settings] : p_request.environments) {
		godot::Dictionary entry;
		if (settings.seed.has_value()) {
			entry["seed"] = static_cast<int64_t>(*settings.seed);
		}
		godot::Dictionary options;
		for (const auto &[key, value] : settings.options) {
			options[to_godot_string(key)] = to_godot_string(value);
		}
		entry["options"] = options;
		request[static_cast<int64_t>(environment_id)] = entry;
	}
	return request;
}

// {actions: [{agent_id: action}]}, one action Dictionary per environment.
godot::Dictionary encode_step(const StepRequest &p_request) {
	godot::Array actions;
	for (const auto &environment : p_request.actions) {
		godot::Dictionary agents;
		for (const auto &[agent_id, action] : environment) {
			agents[to_godot_string(agent_id)] = point_to_variant(action);
		}
		actions.push_back(agents);
	}
	godot::Dictionary request;
	request["actions"] = actions;
	return request;
}

Status not_defined(const char *p_method) {
	return Status::error(StatusCode::FAILED_PRECONDITION,
			std::string("HostTrainingBackend::") + p_method + "() was called before define().");
}

} // namespace

HostTrainingBackend::HostTrainingBackend(godot::Object *p_host) :
		host_id(p_host != nullptr ? p_host->get_instance_id() : 0) {}

Status HostTrainingBackend::set_autoreset_mode(AutoResetMode p_mode) {
	Variant ignored;
	const Status status = call_host(host_id, "initialize_session", ignored);
	if (!status.is_ok()) {
		return status;
	}
	return call_host(host_id, "set_autoreset_mode", ignored, static_cast<int64_t>(p_mode));
}

Status HostTrainingBackend::define(TrainingDefinition &r_definition) {
	Variant value;
	Status status = call_host(host_id, "define", value);
	if (!status.is_ok()) {
		return status;
	}
	TrainingDefinition new_definition;
	status = read_definition(value, new_definition);
	if (!status.is_ok()) {
		return status;
	}
	definition = new_definition;
	r_definition = std::move(new_definition);
	return Status::ok();
}

Status HostTrainingBackend::reset(const ResetRequest &p_request, InitialState &r_initial_state) {
	if (!definition.has_value()) {
		return not_defined("reset");
	}
	Variant value;
	Status status = call_host(host_id, "reset", value, encode_reset(p_request));
	if (!status.is_ok()) {
		return status;
	}
	InitialState state;
	status = read_initial_state(value, *definition, "reset", state);
	if (!status.is_ok()) {
		return status;
	}
	r_initial_state = std::move(state);
	return Status::ok();
}

Status HostTrainingBackend::step(const StepRequest &p_request, StepResult &r_result) {
	if (!definition.has_value()) {
		return not_defined("step");
	}
	Variant value;
	Status status = call_host(host_id, "step", value, encode_step(p_request));
	if (!status.is_ok()) {
		return status;
	}
	StepResult result;
	status = read_step_result(value, *definition, result);
	if (!status.is_ok()) {
		return status;
	}
	r_result = std::move(result);
	return Status::ok();
}

Status HostTrainingBackend::close() {
	definition.reset();
	if (godot::ObjectDB::get_instance(static_cast<uint64_t>(host_id)) == nullptr) {
		return Status::ok();
	}
	Variant ignored;
	return call_host(host_id, "close", ignored);
}

} // namespace schola
