// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/lifecycle/schola_training_host.h"

#include "bindings/environment/schola_agent.h"
#include "bindings/environment/schola_environment.h"
#include "core/environment/interaction_definition.h"

#include "interop/space_dictionary.h"
#include "interop/variant_conversion.h"

#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdint>
#include <limits>
#include <memory>
#include <utility>
#include <vector>

namespace {

std::string to_std_string(const godot::String &p_string) {
	return p_string.utf8().get_data();
}

std::string describe_node(const godot::Node *p_node) {
	return "'" + to_std_string(godot::String(p_node->get_path())) + "'";
}

std::string join_configuration_errors(const godot::PackedStringArray &p_errors) {
	std::string message;
	for (int64_t index = 0; index < p_errors.size(); ++index) {
		if (!message.empty()) {
			message += "; ";
		}
		message += to_std_string(p_errors[index]);
	}
	return message;
}

void collect_environments(godot::Node *p_node, std::vector<ScholaEnvironment *> &r_environments) {
	if (p_node == nullptr) {
		return;
	}

	auto *environment = godot::Object::cast_to<ScholaEnvironment>(p_node);
	if (environment != nullptr) {
		r_environments.push_back(environment);
	}

	for (int64_t i = 0; i < p_node->get_child_count(); ++i) {
		collect_environments(p_node->get_child(i), r_environments);
	}
}

schola::Status check_environment_node(godot::ObjectID p_id, size_t p_index, ScholaEnvironment **r_node = nullptr) {
	godot::Object *object = godot::ObjectDB::get_instance(p_id);
	if (object == nullptr) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"ScholaEnvironment for environment " + std::to_string(p_index) +
						" was freed during the active training session");
	}
	auto *environment = godot::Object::cast_to<ScholaEnvironment>(object);
	if (environment == nullptr) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"object for environment " + std::to_string(p_index) +
						" is no longer a ScholaEnvironment");
	}
	if (environment->get_ancestor_environment() != nullptr) {
		return schola::Status::error(schola::StatusCode::INVALID_DATA,
				"ScholaEnvironment " + describe_node(environment) + ": Nested ScholaEnvironment nodes are unsupported");
	}
	const godot::SceneTree *tree = environment->is_inside_tree() ? environment->get_tree() : nullptr;
	const godot::Node *scene_root = tree != nullptr ? tree->get_current_scene() : nullptr;
	bool belongs_to_scene = false;
	for (const godot::Node *ancestor = environment; ancestor != nullptr; ancestor = ancestor->get_parent()) {
		if (ancestor->is_queued_for_deletion()) {
			return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
					"ScholaEnvironment for environment " + std::to_string(p_index) + " or one of its ancestors is queued for deletion");
		}
		belongs_to_scene = belongs_to_scene || ancestor == scene_root;
	}
	if (!belongs_to_scene) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"ScholaEnvironment for environment " + std::to_string(p_index) + " is outside the current scene");
	}
	if (r_node != nullptr) {
		*r_node = environment;
	}
	return schola::Status::ok();
}

// Works out every agent's spaces now, at session start. The scene configuration
// check never runs _define_spaces(), so without this a broken callback
// would only show up later, when Python asks for the definition. Each agent
// keeps what it resolved, so training's later define() calls get the same
// spaces back without running the callback again.
schola::Status resolve_agent_spaces(godot::ObjectID p_id, size_t p_index) {
	ScholaEnvironment *p_environment = nullptr;
	auto check = check_environment_node(p_id, p_index, &p_environment);
	if (!check.is_ok()) {
		return check;
	}
	const std::string description = describe_node(p_environment);
	const godot::TypedArray<ScholaAgent> agents = p_environment->get_possible_agents();
	check = check_environment_node(p_id, p_index);
	if (!check.is_ok()) {
		return check;
	}
	for (int64_t i = 0; i < agents.size(); ++i) {
		godot::Object *agent_object = agents[i];
		ScholaAgent *agent = godot::Object::cast_to<ScholaAgent>(agent_object);
		if (agent == nullptr) {
			continue;
		}

		// Only the error matters here; the agent saves the spaces itself.
		schola::InteractionDefinition unused;
		const schola::Status status = agent->get_agent()->define(unused);
		check = check_environment_node(p_id, p_index);
		if (!check.is_ok()) {
			return check;
		}
		if (!status.is_ok()) {
			return schola::Status::error(schola::StatusCode::INVALID_DATA,
					"ScholaEnvironment " + description +
							" has invalid configuration: " + status.get_message());
		}
	}
	return schola::Status::ok();
}

// Checks the node before each call, since a callback in another environment may have freed it.
class CheckedEnvironment final : public schola::Environment {
public:
	CheckedEnvironment(godot::ObjectID p_id, size_t p_index, schola::Environment &p_environment) :
			id(p_id), index(p_index), environment(p_environment) {}

	schola::Status initialize(std::map<schola::AgentId, schola::InteractionDefinition> &r_agents) override {
		const schola::Status status = check_environment_node(id, index);
		return status.is_ok() ? environment.initialize(r_agents) : status;
	}

	schola::Status reset(const schola::ResetSettings &p_settings,
			std::map<schola::AgentId, schola::InitialAgentState> &r_states) override {
		const schola::Status status = check_environment_node(id, index);
		return status.is_ok() ? environment.reset(p_settings, r_states) : status;
	}

	schola::Status step(const std::map<schola::AgentId, schola::Point> &p_actions,
			std::map<schola::AgentId, schola::AgentState> &r_states) override {
		const schola::Status status = check_environment_node(id, index);
		return status.is_ok() ? environment.step(p_actions, r_states) : status;
	}

	schola::Status get_agents(std::vector<schola::Agent *> &r_agents) const override {
		const schola::Status status = check_environment_node(id, index);
		return status.is_ok() ? environment.get_agents(r_agents) : status;
	}

private:
	godot::ObjectID id;
	size_t index;
	schola::Environment &environment; // Owned by the node behind id.
};

godot::Dictionary encode_status(const schola::Status &status) {
	godot::Dictionary dict;
	dict["code"] = static_cast<int>(status.get_code());
	dict["message"] = godot::String::utf8(status.get_message().c_str());
	return dict;
}

godot::Dictionary encode_training_definition(const schola::TrainingDefinition &defn) {
	godot::Array environments;
	for (auto &environment : defn.environments) {
		godot::Dictionary agents;
		for (auto &[agent_id, definition] : environment.agents) {
			godot::Dictionary encoded_definition;
			encoded_definition["observation_space"] = schola::space_to_dictionary(definition.observation_space);
			encoded_definition["action_space"] = schola::space_to_dictionary(definition.action_space);
			encoded_definition["agent_type"] = godot::String::utf8(definition.agent_type.c_str());
			agents[godot::String::utf8(agent_id.c_str())] = encoded_definition;
		}

		godot::Dictionary encoded_environment;
		encoded_environment["agents"] = agents;
		environments.append(encoded_environment);
	}

	godot::Dictionary result;
	result["environments"] = environments;
	return result;
}

schola::Status decode_step_request(const godot::Dictionary &dict,
		schola::TrainingDefinition &definition, schola::StepRequest &r_request) {
	if (!dict.has("actions") || dict["actions"].get_type() != godot::Variant::ARRAY) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
				"step request actions must be an array");
	}

	godot::Array actions = dict["actions"];
	if (actions.size() != static_cast<int64_t>(definition.environments.size())) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
				"step request must contain one action map per environment");
	}

	schola::StepRequest request;
	request.actions.reserve(actions.size());
	for (int64_t environment_index = 0; environment_index < actions.size(); ++environment_index) {
		if (actions[environment_index].get_type() != godot::Variant::DICTIONARY) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
					"each environment action entry must be a dictionary");
		}

		godot::Dictionary environment_actions = actions[environment_index];
		schola::EnvironmentDefinition &environment_definition = definition.environments[environment_index];
		std::map<schola::AgentId, schola::Point> decoded_actions;

		godot::Array agent_ids = environment_actions.keys();
		for (int64_t agent_index = 0; agent_index < agent_ids.size(); ++agent_index) {
			godot::Variant agent_id_value = agent_ids[agent_index];
			if (agent_id_value.get_type() != godot::Variant::STRING) {
				return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
						"step request agent IDs must be strings");
			}

			schola::AgentId agent_id = to_std_string(godot::String(agent_id_value));
			auto agent_definition = environment_definition.agents.find(agent_id);
			if (agent_definition == environment_definition.agents.end()) {
				return schola::Status::error(schola::StatusCode::NOT_FOUND,
						"Agent '" + agent_id + "': not part of this environment");
			}

			schola::Point point;
			schola::Status status = schola::variant_to_point(
					environment_actions[agent_id_value],
					agent_definition->second.action_space,
					point);

			if (!status.is_ok()) {
				return schola::Status::error(status.get_code(),
						"Agent '" + agent_id + "': rejected action: " + status.get_message());
			}
			decoded_actions.emplace(agent_id, std::move(point));
		}

		request.actions.push_back(std::move(decoded_actions));
	}

	r_request = std::move(request);
	return schola::Status::ok();
}

schola::Status decode_reset_request(const godot::Dictionary &dict, schola::ResetRequest &r_request) {
	schola::ResetRequest request;
	const godot::Array keys = dict.keys();
	for (int64_t i = 0; i < keys.size(); ++i) {
		const godot::Variant key = keys[i];
		if (key.get_type() != godot::Variant::INT) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
					"reset environment IDs must be integers");
		}
		const int64_t environment_id = key;
		if (environment_id < 0 || environment_id > std::numeric_limits<schola::EnvironmentId>::max()) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
					"reset environment ID is outside the supported range");
		}
		if (dict[key].get_type() != godot::Variant::DICTIONARY) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
					"reset settings for environment " + std::to_string(environment_id) + " must be a dictionary");
		}
		const godot::Dictionary entry = dict[key];
		// A misspelled key would otherwise give a silent, unseeded default reset
		const godot::Array setting_keys = entry.keys();
		for (int64_t j = 0; j < setting_keys.size(); ++j) {
			const godot::Variant setting = setting_keys[j];
			if (setting.get_type() != godot::Variant::STRING || (godot::String(setting) != "seed" && godot::String(setting) != "options")) {
				return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
						"reset settings for environment " + std::to_string(environment_id) + " have unknown key " +
								to_std_string(setting.stringify()) + "; only \"seed\" and \"options\" are allowed");
			}
		}
		schola::ResetSettings settings;

		if (entry.has("seed")) {
			const godot::Variant seed = entry["seed"];
			if (seed.get_type() != godot::Variant::INT ||
					static_cast<int64_t>(seed) < std::numeric_limits<int32_t>::min() ||
					static_cast<int64_t>(seed) > std::numeric_limits<int32_t>::max()) {
				return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
						"reset seed must be a signed 32-bit integer");
			}
			settings.seed = static_cast<int32_t>(static_cast<int64_t>(seed));
		}

		if (entry.has("options")) {
			if (entry["options"].get_type() != godot::Variant::DICTIONARY) {
				return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
						"reset options must be a dictionary of strings");
			}
			const godot::Dictionary options = entry["options"];
			const godot::Array option_keys = options.keys();
			for (int64_t j = 0; j < option_keys.size(); ++j) {
				const godot::Variant option_key = option_keys[j];
				const godot::Variant value = options[option_key];
				if (option_key.get_type() != godot::Variant::STRING || value.get_type() != godot::Variant::STRING) {
					return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
							"reset option keys and values must be strings");
				}
				settings.options.emplace(to_std_string(godot::String(option_key)), to_std_string(godot::String(value)));
			}
		}

		request.environments.emplace(static_cast<schola::EnvironmentId>(environment_id), std::move(settings));
	}
	r_request = std::move(request);
	return schola::Status::ok();
}

godot::Dictionary encode_info(const std::map<std::string, std::string> &info) {
	godot::Dictionary result;
	for (auto &[key, value] : info) {
		result[godot::String::utf8(key.c_str())] = godot::String::utf8(value.c_str());
	}
	return result;
}

godot::Dictionary encode_initial_state(const schola::InitialState &state) {
	godot::Dictionary environments;
	for (auto &[environment_id, environment] : state.environments) {
		godot::Dictionary agents;
		for (auto &[agent_id, agent] : environment.agents) {
			godot::Dictionary encoded_agent;
			encoded_agent["observation"] = schola::point_to_variant(agent.observation);
			encoded_agent["info"] = encode_info(agent.info);
			agents[godot::String::utf8(agent_id.c_str())] = encoded_agent;
		}
		environments[environment_id] = agents;
	}
	return environments;
}

godot::Dictionary encode_step_result(const schola::StepResult &result) {
	godot::Array environments;
	for (auto &environment : result.state.environments) {
		godot::Dictionary agents;
		for (auto &[agent_id, agent] : environment.agents) {
			if (agent.paused) {
				continue;
			}
			godot::Dictionary encoded_agent;
			encoded_agent["observation"] = schola::point_to_variant(agent.observation);
			encoded_agent["reward"] = agent.reward;
			encoded_agent["terminated"] = agent.terminated;
			encoded_agent["truncated"] = agent.truncated;
			encoded_agent["info"] = encode_info(agent.info);
			agents[godot::String::utf8(agent_id.c_str())] = encoded_agent;
		}
		environments.append(agents);
	}

	godot::Dictionary encoded;
	encoded["state"] = environments;
	encoded["initial_state"] = encode_initial_state(result.initial_state);
	return encoded;
}

godot::Dictionary encode_result(const schola::Status &status, const godot::Variant &value = godot::Variant()) {
	godot::Dictionary result;
	result["status"] = encode_status(status);
	result["value"] = value;
	return result;
}

} // namespace

schola::Status ScholaTrainingHost::initialize_session_core() {
	if (session_state != SessionState::CONFIGURING) {
		const char *message = session_state == SessionState::ACTIVE ? "training session is already initialized" : "training session is shutting down or closed";
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION, message);
	}

	godot::SceneTree *tree = get_tree();
	if (tree == nullptr) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"training host is not inside a scene tree");
	}

	godot::Node *scene_root = tree->get_current_scene();
	if (scene_root == nullptr) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"scene tree has no current scene");
	}

	std::vector<godot::ObjectID> discovered_ids;
	{
		std::vector<ScholaEnvironment *> discovered_environments;
		collect_environments(scene_root, discovered_environments);
		discovered_ids.reserve(discovered_environments.size());
		for (const auto *environment_node : discovered_environments) {
			discovered_ids.emplace_back(environment_node->get_instance_id());
		}
	}
	if (discovered_ids.empty()) {
		return schola::Status::error(schola::StatusCode::NOT_FOUND,
				"current scene " + describe_node(scene_root) +
						" contains no ScholaEnvironment nodes; add at least one trainable environment to the scene");
	}

	std::vector<std::unique_ptr<schola::Environment>> checked;
	std::vector<std::unique_ptr<schola::EnvironmentLifecycle>> lifecycles;
	checked.reserve(discovered_ids.size());
	lifecycles.reserve(discovered_ids.size());

	// Configuration may call the scene's _get_possible_agents() scripts.
	for (size_t i = 0; i < discovered_ids.size(); ++i) {
		ScholaEnvironment *environment_node = nullptr;
		const auto id = discovered_ids[i];
		auto status = check_environment_node(id, i, &environment_node);
		if (!status.is_ok()) {
			return status;
		}
		const godot::PackedStringArray configuration_errors = environment_node->get_scene_configuration_errors();
		status = check_environment_node(id, i, &environment_node);
		if (!status.is_ok()) {
			return status;
		}
		if (!configuration_errors.is_empty()) {
			return schola::Status::error(schola::StatusCode::INVALID_DATA,
					"ScholaEnvironment " + describe_node(environment_node) +
							" has invalid configuration: " + join_configuration_errors(configuration_errors));
		}

		status = resolve_agent_spaces(id, i);
		if (!status.is_ok()) {
			return status;
		}
		status = check_environment_node(id, i, &environment_node);
		if (!status.is_ok()) {
			return status;
		}

		schola::Environment *environment = environment_node->get_environment();
		if (environment == nullptr) {
			return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
					"ScholaEnvironment " + describe_node(environment_node) +
							" has no core environment adapter; ensure it is inside the active scene tree");
		}

		checked.push_back(std::make_unique<CheckedEnvironment>(id, i, *environment));
		lifecycles.push_back(std::make_unique<schola::EnvironmentLifecycle>(
				static_cast<schola::EnvironmentId>(i),
				*checked.back()));
	}

	// The last callback may have removed an environment already checked above.
	for (size_t i = 0; i < discovered_ids.size(); ++i) {
		const auto status = check_environment_node(discovered_ids[i], i);
		if (!status.is_ok()) {
			return status;
		}
	}
	schola::Status result = coordinator.set_lifecycles(std::move(lifecycles));
	if (!result.is_ok()) {
		return result;
	}

	environment_ids = std::move(discovered_ids);
	checked_environments = std::move(checked);
	session_state = SessionState::ACTIVE;
	return schola::Status::ok();
}

schola::Status ScholaTrainingHost::require_active_session() const {
	// A nested define, reset or step would change lifecycle state underneath
	// the call that is still running.
	if (in_coordinator) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"ScholaTrainingHost cannot be called from a training callback; use call_deferred()");
	}
	if (session_state == SessionState::ACTIVE) {
		return schola::Status::ok();
	}

	const char *message = session_state == SessionState::CONFIGURING ? "training session is not initialized" : "training session is shutting down or closed";
	return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION, message);
}

schola::Status ScholaTrainingHost::require_main_thread() {
	if (godot::Thread::is_main_thread()) {
		return schola::Status::ok();
	}

	return schola::Status::error(
			schola::StatusCode::FAILED_PRECONDITION,
			"ScholaTrainingHost operations must run on the Godot main thread");
}

schola::Status ScholaTrainingHost::validate_environment_nodes() const {
	for (size_t index = 0; index < environment_ids.size(); ++index) {
		const schola::Status status = check_environment_node(environment_ids[index], index);
		if (!status.is_ok()) {
			return status;
		}
	}
	// Callbacks can introduce an unregistered nested environment. Validate the
	// whole active scene, not just the IDs captured when the session started.
	const godot::SceneTree *tree = get_tree();
	godot::Node *scene_root = tree != nullptr ? tree->get_current_scene() : nullptr;
	if (scene_root == nullptr) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"training session has no active scene");
	}
	std::vector<ScholaEnvironment *> scene_environments;
	collect_environments(scene_root, scene_environments);
	for (const auto *environment : scene_environments) {
		if (environment->get_ancestor_environment() != nullptr) {
			return schola::Status::error(schola::StatusCode::INVALID_DATA,
					"ScholaEnvironment " + describe_node(environment) + ": Nested ScholaEnvironment nodes are unsupported");
		}
	}
	return schola::Status::ok();
}

schola::Status ScholaTrainingHost::fail_session(const schola::Status &p_failure) {
	(void)shutdown_core();
	return p_failure;
}

schola::Status ScholaTrainingHost::handle_coordinator_result(const schola::Status &p_status) {
	if (!p_status.is_ok() && coordinator.get_state() == schola::CoordinatorState::FAULTED) {
		return fail_session(p_status);
	}
	if (p_status.is_ok()) {
		const schola::Status nodes = validate_environment_nodes();
		if (!nodes.is_ok()) {
			return fail_session(nodes);
		}
	}
	return p_status;
}

// Runs a coordinator call that can reach gameplay callbacks. If one of them
// closes the host, the close is carried out here, once the coordinator has
// returned, and the call reports that the session was closed.
schola::Status ScholaTrainingHost::run_coordinator(const std::function<schola::Status()> &p_call) {
	in_coordinator = true;
	const schola::Status status = p_call();
	in_coordinator = false;
	if (close_requested) {
		close_requested = false;
		const schola::Status closed = schola::Status::error(schola::StatusCode::CLOSED,
				"training session was closed by a callback while it was running");
		return fail_session(status.is_ok() ? closed : status);
	}
	return handle_coordinator_result(status);
}

schola::Status ScholaTrainingHost::shutdown_core() {
	if (session_state == SessionState::CLOSED || session_state == SessionState::SHUTTING_DOWN) {
		return schola::Status::ok();
	}
	// close() or leaving the tree from inside a callback. Closing now would free
	// the lifecycles that are still on the call stack, so wait for them to return.
	if (in_coordinator) {
		close_requested = true;
		return schola::Status::ok();
	}

	session_state = SessionState::SHUTTING_DOWN;
	schola::Status status = coordinator.close();
	training_definition.reset();
	// Hand the environments back, so the next session's host can initialize
	// them again. Nodes freed during the session are simply skipped.
	for (const godot::ObjectID &id : environment_ids) {
		ScholaEnvironment *environment = godot::Object::cast_to<ScholaEnvironment>(godot::ObjectDB::get_instance(id));
		if (environment != nullptr) {
			environment->release_environment();
		}
	}
	environment_ids.clear();
	checked_environments.clear();
	session_state = SessionState::CLOSED;
	return status;
}

godot::Dictionary ScholaTrainingHost::initialize_session() {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	return encode_result(initialize_session_core());
}

godot::Dictionary ScholaTrainingHost::set_autoreset_mode(int64_t p_mode) {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	schola::Status nodes = validate_environment_nodes();
	if (!nodes.is_ok()) {
		return encode_result(fail_session(nodes));
	}

	// AutoResetMode is an int underneath, so a wider value would wrap into a valid
	// mode (2^32 becomes SAME_STEP). Reject it before the cast; the coordinator
	// checks everything in range.
	if (p_mode < std::numeric_limits<int32_t>::min() || p_mode > std::numeric_limits<int32_t>::max()) {
		return encode_result(schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "unknown autoreset mode"));
	}
	return encode_result(coordinator.set_autoreset_mode(
			static_cast<schola::AutoResetMode>(p_mode)));
}

godot::Dictionary ScholaTrainingHost::define() {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	schola::Status nodes = validate_environment_nodes();
	if (!nodes.is_ok()) {
		return encode_result(fail_session(nodes));
	}

	schola::TrainingDefinition definition;
	schola::Status status = run_coordinator([&] { return coordinator.define(definition); });
	if (!status.is_ok()) {
		return encode_result(status);
	}

	training_definition = definition;
	return encode_result(status, encode_training_definition(definition));
}

godot::Dictionary ScholaTrainingHost::reset(const godot::Dictionary &p_request) {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	schola::Status nodes = validate_environment_nodes();
	if (!nodes.is_ok()) {
		return encode_result(fail_session(nodes));
	}

	schola::ResetRequest request;
	schola::Status status = decode_reset_request(p_request, request);
	if (!status.is_ok()) {
		return encode_result(status);
	}

	schola::InitialState state;
	status = run_coordinator([&] { return coordinator.reset(request, state); });
	return status.is_ok() ? encode_result(status, encode_initial_state(state)) : encode_result(status);
}

godot::Dictionary ScholaTrainingHost::step(const godot::Dictionary &p_request) {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	schola::Status nodes = validate_environment_nodes();
	if (!nodes.is_ok()) {
		return encode_result(fail_session(nodes));
	}

	if (!training_definition.has_value()) {
		return encode_result(schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"training session is not defined"));
	}

	schola::StepRequest request;
	schola::Status status = decode_step_request(p_request, *training_definition, request);
	if (!status.is_ok()) {
		return encode_result(status);
	}

	schola::StepResult result;
	status = run_coordinator([&] { return coordinator.step(request, result); });
	return status.is_ok() ? encode_result(status, encode_step_result(result)) : encode_result(status);
}

godot::Dictionary ScholaTrainingHost::close() {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	return encode_result(shutdown_core());
}

bool ScholaTrainingHost::is_session_active() const {
	return session_state == SessionState::ACTIVE;
}

void ScholaTrainingHost::_exit_tree() {
	schola::Status status = shutdown_core();
	if (!status.is_ok()) {
		godot::UtilityFunctions::push_error(
				godot::String("ScholaTrainingHost shutdown failed: ") + godot::String::utf8(status.get_message().c_str()));
	}
}

void ScholaTrainingHost::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("initialize_session"), &ScholaTrainingHost::initialize_session);
	godot::ClassDB::bind_method(godot::D_METHOD("set_autoreset_mode", "mode"), &ScholaTrainingHost::set_autoreset_mode);
	godot::ClassDB::bind_method(godot::D_METHOD("define"), &ScholaTrainingHost::define);
	godot::ClassDB::bind_method(godot::D_METHOD("reset", "request"), &ScholaTrainingHost::reset);
	godot::ClassDB::bind_method(godot::D_METHOD("step", "request"), &ScholaTrainingHost::step);
	godot::ClassDB::bind_method(godot::D_METHOD("close"), &ScholaTrainingHost::close);
	godot::ClassDB::bind_method(godot::D_METHOD("is_session_active"), &ScholaTrainingHost::is_session_active);
}
