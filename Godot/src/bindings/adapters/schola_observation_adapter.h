// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/adapters/stacker.h"

#include <godot_cpp/classes/resource.hpp>

#include <memory>

class ScholaObservationAdapter : public godot::Resource {
	GDCLASS(ScholaObservationAdapter, godot::Resource)

public:
	virtual schola::Status create(const schola::Space &p_space, std::unique_ptr<schola::ObservationAdapter> &r_adapter) const = 0;

protected:
	static void _bind_methods() {}
};

class ScholaStacker : public ScholaObservationAdapter {
	GDCLASS(ScholaStacker, ScholaObservationAdapter)

public:
	void set_stack_size(int32_t p_size) { stack_size = p_size; }
	int32_t get_stack_size() const { return stack_size; }
	void set_default_point(const godot::Variant &p_point) { default_point = p_point; }
	godot::Variant get_default_point() const { return default_point; }
	void set_stack_dimension(int32_t p_axis) { stack_dimension = p_axis; }
	int32_t get_stack_dimension() const { return stack_dimension; }
	void set_add_new_dimension(bool p_enabled) { add_new_dimension = p_enabled; }
	bool get_add_new_dimension() const { return add_new_dimension; }
	void set_output_kind(int32_t p_kind) { output_kind = p_kind; }
	int32_t get_output_kind() const { return output_kind; }

	schola::Status create(const schola::Space &p_space, std::unique_ptr<schola::ObservationAdapter> &r_adapter) const override;

protected:
	static void _bind_methods();

private:
	int32_t stack_size = 4;
	godot::Variant default_point;
	int32_t stack_dimension = 0;
	bool add_new_dimension = true;
	int32_t output_kind = 0;
};
