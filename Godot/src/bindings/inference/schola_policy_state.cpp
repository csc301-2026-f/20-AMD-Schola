// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/inference/schola_policy_state.h"

#include "core/policy/policy_state.h"
#include "interop/godot_status.h"

#include <godot_cpp/core/class_db.hpp>

ScholaPolicyState::ScholaPolicyState() = default;

ScholaPolicyState::~ScholaPolicyState() = default;

void ScholaPolicyState::reset() {
	if (state != nullptr) {
		state->reset();
	}
}

godot::Error ScholaPolicyState::copy_from(const godot::Ref<ScholaPolicyState> &p_other) {
	last_error = godot::String();
	if (state == nullptr || p_other.is_null() || p_other->state == nullptr) {
		return report_failure("ScholaPolicyState.copy_from: both states must come from ScholaOnnxPolicy.create_state()", godot::ERR_INVALID_PARAMETER, &last_error);
	}
	schola::Status status = state->copy_from(*p_other->state);
	if (!status.is_ok()) {
		return report_failure("ScholaPolicyState.copy_from", status, &last_error);
	}
	return godot::OK;
}

godot::String ScholaPolicyState::get_last_error() const {
	return last_error;
}

godot::String ScholaPolicyState::_to_string() const {
	return state == nullptr ? godot::String("ScholaPolicyState(empty)") : to_godot_string(state->to_string());
}

schola::PolicyState *ScholaPolicyState::get_state() const {
	return state.get();
}

void ScholaPolicyState::set_state(std::unique_ptr<schola::PolicyState> p_state) {
	state = std::move(p_state);
}

void ScholaPolicyState::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("reset"), &ScholaPolicyState::reset);
	godot::ClassDB::bind_method(godot::D_METHOD("copy_from", "other"), &ScholaPolicyState::copy_from);
	godot::ClassDB::bind_method(godot::D_METHOD("get_last_error"), &ScholaPolicyState::get_last_error);
}
