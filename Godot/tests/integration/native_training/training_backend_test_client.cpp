// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Test-only stand-in for Python, so GdUnit4 can drive HostTrainingBackend (the
// training extension's link to ScholaTrainingHost) without gRPC. It makes the
// same calls ConnectorLoop makes, in the same order, and turns each result into
// a plain Dictionary. Compiled into the training extension only with
// integration_tests=yes.
#include "core/lifecycle/training_backend.h"
#include "interop/space_dictionary.h"
#include "interop/variant_conversion.h"
#include "training/bindings/host_training_backend.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>

class ScholaTrainingTestClient : public godot::RefCounted {
	GDCLASS(ScholaTrainingTestClient, godot::RefCounted)

public:
	// Points the client at a ScholaTrainingHost node, the way
	// ScholaTrainingConnector does when a session starts.
	void use_host(godot::Object *p_host) {
		backend = std::make_unique<schola::HostTrainingBackend>(p_host);
		definition.reset();
	}

	// Python's StartGymConnector. p_mode is a schola::AutoResetMode value.
	godot::Dictionary start(int64_t p_mode) {
		if (!backend) {
			return no_host();
		}
		return response(backend->set_autoreset_mode(static_cast<schola::AutoResetMode>(p_mode)));
	}

	// Python's RequestTrainingDefinition. The value is what the backend rebuilt
	// from the host's reply, written back out with space_to_dictionary():
	// [{agent_id: {observation_space, action_space, agent_type}}, ...]
	godot::Dictionary define() {
		if (!backend) {
			return no_host();
		}
		schola::TrainingDefinition result;
		const schola::Status status = backend->define(result);
		godot::Dictionary reply = response(status);
		if (!status.is_ok()) {
			return reply;
		}

		godot::Array environments;
		for (const schola::EnvironmentDefinition &environment : result.environments) {
			godot::Dictionary agents;
			for (const auto &[id, agent] : environment.agents) {
				godot::Dictionary entry;
				entry["observation_space"] = schola::space_to_dictionary(agent.observation_space);
				entry["action_space"] = schola::space_to_dictionary(agent.action_space);
				entry["agent_type"] = to_godot_string(agent.agent_type);
				agents[to_godot_string(id)] = entry;
			}
			environments.push_back(agents);
		}
		definition = std::move(result);
		reply["value"] = environments;
		return reply;
	}

	// Python's reset. p_seeds is {environment_id: seed}; leave an environment
	// out to reset it without a seed. The value is {environment_id: {agent_id: observation}}.
	godot::Dictionary reset(const godot::Dictionary &p_seeds) {
		if (!backend) {
			return no_host();
		}
		schola::ResetRequest request;
		const godot::Array ids = p_seeds.keys();
		for (int64_t i = 0; i < ids.size(); ++i) {
			const int64_t id = ids[i];
			const int64_t seed = p_seeds[ids[i]];
			request.environments[static_cast<schola::EnvironmentId>(id)].seed = static_cast<int32_t>(seed);
		}

		schola::InitialState state;
		const schola::Status status = backend->reset(request, state);
		godot::Dictionary reply = response(status);
		if (status.is_ok()) {
			reply["value"] = encode_initial_state(state);
		}
		return reply;
	}

	// Python's step. p_actions has one {agent_id: action} Dictionary per
	// environment, in definition order. The value is
	// {state: [{agent_id: {observation, reward, terminated, truncated}}], initial_state: {...}}.
	godot::Dictionary step(const godot::Array &p_actions) {
		if (!backend) {
			return no_host();
		}
		if (!definition) {
			return response(schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
					"Call define() first, so actions can be converted with the agents' action spaces."));
		}

		// Turn each GDScript action into a Point with that agent's action space,
		// as the gRPC connector does with Python's protobuf actions.
		schola::StepRequest request;
		for (int64_t environment = 0; environment < p_actions.size(); ++environment) {
			const godot::Dictionary actions = p_actions[environment];
			std::map<schola::AgentId, schola::Point> points;
			const godot::Array ids = actions.keys();
			for (int64_t i = 0; i < ids.size(); ++i) {
				const schola::AgentId id = godot::String(ids[i]).utf8().get_data();
				// Exceptions are off in this build, so look agents up without .at().
				const schola::Space *space = find_action_space(environment, id);
				if (space == nullptr) {
					return response(schola::Status::error(schola::StatusCode::NOT_FOUND,
							"No agent '" + id + "' in environment " + std::to_string(environment) + " of the definition."));
				}
				schola::Point point;
				const schola::Status conversion = schola::variant_to_point(actions[ids[i]], *space, point);
				if (!conversion.is_ok()) {
					return response(conversion);
				}
				points.emplace(id, std::move(point));
			}
			request.actions.push_back(std::move(points));
		}

		schola::StepResult result;
		const schola::Status status = backend->step(request, result);
		godot::Dictionary reply = response(status);
		if (!status.is_ok()) {
			return reply;
		}

		godot::Array environments;
		for (const schola::EnvironmentState &environment : result.state.environments) {
			godot::Dictionary agents;
			for (const auto &[id, agent] : environment.agents) {
				godot::Dictionary entry;
				entry["observation"] = schola::point_to_variant(agent.observation);
				entry["reward"] = agent.reward;
				entry["terminated"] = agent.terminated;
				entry["truncated"] = agent.truncated;
				agents[to_godot_string(id)] = entry;
			}
			environments.push_back(agents);
		}
		godot::Dictionary value;
		value["state"] = environments;
		value["initial_state"] = encode_initial_state(result.initial_state);
		reply["value"] = value;
		return reply;
	}

	// Python's close.
	godot::Dictionary close() {
		if (!backend) {
			return no_host();
		}
		definition.reset();
		return response(backend->close());
	}

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("use_host", "host"), &ScholaTrainingTestClient::use_host);
		godot::ClassDB::bind_method(godot::D_METHOD("start", "autoreset_mode"), &ScholaTrainingTestClient::start);
		godot::ClassDB::bind_method(godot::D_METHOD("define"), &ScholaTrainingTestClient::define);
		godot::ClassDB::bind_method(godot::D_METHOD("reset", "seeds"), &ScholaTrainingTestClient::reset);
		godot::ClassDB::bind_method(godot::D_METHOD("step", "actions"), &ScholaTrainingTestClient::step);
		godot::ClassDB::bind_method(godot::D_METHOD("close"), &ScholaTrainingTestClient::close);
	}

private:
	// The saved action space for one agent, or null if define() didn't list it.
	const schola::Space *find_action_space(int64_t p_environment, const schola::AgentId &p_id) const {
		if (p_environment < 0 || p_environment >= static_cast<int64_t>(definition->environments.size())) {
			return nullptr;
		}
		const auto &agents = definition->environments[static_cast<size_t>(p_environment)].agents;
		const auto agent = agents.find(p_id);
		return agent == agents.end() ? nullptr : &agent->second.action_space;
	}

	static godot::String to_godot_string(const std::string &p_text) {
		return godot::String::utf8(p_text.c_str());
	}

	// {environment_id: {agent_id: observation}}
	static godot::Dictionary encode_initial_state(const schola::InitialState &p_state) {
		godot::Dictionary environments;
		for (const auto &[environment_id, environment] : p_state.environments) {
			godot::Dictionary agents;
			for (const auto &[id, agent] : environment.agents) {
				agents[to_godot_string(id)] = schola::point_to_variant(agent.observation);
			}
			environments[static_cast<int64_t>(environment_id)] = agents;
		}
		return environments;
	}

	// {ok, code, message}, the same shape as ScholaEnvironmentTestDriver.
	static godot::Dictionary response(const schola::Status &p_status) {
		godot::Dictionary result;
		result["ok"] = p_status.is_ok();
		result["code"] = static_cast<int64_t>(p_status.get_code());
		result["message"] = to_godot_string(p_status.get_message());
		return result;
	}

	static godot::Dictionary no_host() {
		return response(schola::Status::error(schola::StatusCode::FAILED_PRECONDITION, "Call use_host() first."));
	}

	std::unique_ptr<schola::TrainingBackend> backend;
	// Kept from define(), because step() needs each agent's action space.
	std::optional<schola::TrainingDefinition> definition;
};

void register_schola_training_test_client() {
	GDREGISTER_CLASS(ScholaTrainingTestClient);
}
