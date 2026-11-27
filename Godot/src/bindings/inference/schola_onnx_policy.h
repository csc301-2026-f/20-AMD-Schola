// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/inference/schola_policy_state.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <memory>

namespace schola {
class OnnxPolicy;
class PolicyState;
struct InteractionDefinition;
} // namespace schola

class ScholaAgent;

class ScholaOnnxPolicy : public godot::Resource {
	GDCLASS(ScholaOnnxPolicy, godot::Resource)

public:
	ScholaOnnxPolicy();
	~ScholaOnnxPolicy() override;

	void set_model_path(const godot::String &p_path);
	godot::String get_model_path() const;
	godot::PackedInt64Array get_state_sequence_lengths() const;

	godot::Error load();
	bool is_loaded() const;
	bool is_recurrent() const;
	godot::String get_last_error() const;
	godot::PackedStringArray get_input_names() const;
	godot::PackedStringArray get_output_names() const;

	godot::Error initialize(ScholaAgent *p_agent);
	bool is_initialized() const;
	godot::Ref<ScholaPolicyState> create_state();
	godot::Variant infer(const godot::Variant &p_observation, const godot::Ref<ScholaPolicyState> &p_state = godot::Ref<ScholaPolicyState>());

	schola::OnnxPolicy *get_policy() const;
	// The spaces the policy was initialized with, or null before initialize().
	const schola::InteractionDefinition *get_definition() const;

protected:
	static void _bind_methods();

private:
	godot::String model_path;
	godot::String loaded_path;
	bool sequence_warned = false;
	godot::String last_error;
	std::unique_ptr<schola::OnnxPolicy> policy;
	std::unique_ptr<schola::InteractionDefinition> definition;
	std::unique_ptr<schola::PolicyState> stateless_state;
};
