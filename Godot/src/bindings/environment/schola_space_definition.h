// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/spaces/schola_space.h"

#include <godot_cpp/classes/ref_counted.hpp>

/** Typed result of ScholaAgent::_define_spaces(); both resources are validated at initialization. */
class ScholaSpaceDefinition : public godot::RefCounted {
	GDCLASS(ScholaSpaceDefinition, godot::RefCounted)

public:
	/** Keeps references to both resources; the agent captures its own validated core snapshot. */
	static godot::Ref<ScholaSpaceDefinition> create(const godot::Ref<ScholaSpace> &p_observation, const godot::Ref<ScholaSpace> &p_action);
	void set_observation(const godot::Ref<ScholaSpace> &p_observation);
	godot::Ref<ScholaSpace> get_observation() const;
	void set_action(const godot::Ref<ScholaSpace> &p_action);
	godot::Ref<ScholaSpace> get_action() const;

protected:
	static void _bind_methods();

private:
	godot::Ref<ScholaSpace> observation;
	godot::Ref<ScholaSpace> action;
};
