// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/inference/schola_onnx_policy.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cstdint>
#include <memory>

namespace schola {
class SimpleStepper;
class Status;
} // namespace schola

class ScholaAgent;

class ScholaInferenceStepper : public godot::Node {
	GDCLASS(ScholaInferenceStepper, godot::Node)

public:
	ScholaInferenceStepper();
	~ScholaInferenceStepper() override;

	void set_policy(const godot::Ref<ScholaOnnxPolicy> &p_policy);
	godot::Ref<ScholaOnnxPolicy> get_policy() const;
	void set_agents(const godot::TypedArray<godot::NodePath> &p_agents);
	godot::TypedArray<godot::NodePath> get_agents() const;
	void set_enabled(bool p_enabled);
	bool is_enabled() const;

	godot::Error add_agent(ScholaAgent *p_agent);
	int32_t remove_agent(ScholaAgent *p_agent);
	void reset_state(ScholaAgent *p_agent);
	void reset_states();
	godot::Error step();

	godot::PackedStringArray get_configuration_errors() const;
	godot::PackedStringArray _get_configuration_warnings() const override;
	void _ready() override;
	void _physics_process(double p_delta) override;

protected:
	static void _bind_methods();

private:
	godot::Error prepare(ScholaAgent *p_agent);
	void on_agent_exiting(godot::Object *p_agent);
	godot::Error report(const godot::String &p_message, godot::Error p_error);
	godot::Error report(const godot::String &p_context, const schola::Status &p_status);

	godot::Ref<ScholaOnnxPolicy> policy;
	godot::TypedArray<godot::NodePath> agents;
	bool enabled = true;
	bool stepping = false;
	std::unique_ptr<schola::SimpleStepper> stepper;
	godot::String last_step_error;
};
