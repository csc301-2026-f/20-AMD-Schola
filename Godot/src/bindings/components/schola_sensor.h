// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
#pragma once
#include "bindings/spaces/schola_space.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <vector>

/** Reusable sensor; belongs to its nearest ScholaAgent ancestor. */
class ScholaSensor : public godot::Node {
	GDCLASS(ScholaSensor, godot::Node)
public:
	ScholaSensor();
	~ScholaSensor() override;
	virtual bool observe_value(godot::Variant &value);
	void set_component_id(const godot::String &value);
	godot::String get_component_id() const;
	godot::String get_resolved_component_id() const;
	void set_space(const godot::Ref<ScholaSpace> &value);
	godot::Ref<ScholaSpace> get_space() const;
	GDVIRTUAL0RC(godot::PackedStringArray, _get_component_errors)
	godot::PackedStringArray get_configuration_errors(bool check_duplicates = true) const;
	godot::PackedStringArray _get_configuration_warnings() const override;
	GDVIRTUAL0R(godot::Variant, _observe)
protected:
	static void _bind_methods();
	void _notification(int what);

private:
	void refresh_warnings();
	void script_updated();
	std::vector<godot::Ref<godot::Script>> watched_scripts;
	godot::String component_id;
	godot::Ref<ScholaSpace> space;
};
