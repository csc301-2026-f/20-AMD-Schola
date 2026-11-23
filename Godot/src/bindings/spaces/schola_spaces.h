// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/spaces/schola_box_space.h"
#include "bindings/spaces/schola_dict_space.h"
#include "bindings/spaces/schola_discrete_space.h"
#include "bindings/spaces/schola_multi_binary_space.h"
#include "bindings/spaces/schola_multi_discrete_space.h"
#include "core/spaces/space_kind.h"

#include <godot_cpp/classes/ref_counted.hpp>

/** Static constructors for existing space resources; validate with get_definition_error(). */
class ScholaSpaces : public godot::RefCounted {
	GDCLASS(ScholaSpaces, godot::RefCounted)

public:
	enum DType {
		FLOAT32 = static_cast<int32_t>(schola::DType::FLOAT32),
		UINT8 = static_cast<int32_t>(schola::DType::UINT8),
		UINT16 = static_cast<int32_t>(schola::DType::UINT16),
		UINT32 = static_cast<int32_t>(schola::DType::UINT32),
		UINT64 = static_cast<int32_t>(schola::DType::UINT64),
		INT8 = static_cast<int32_t>(schola::DType::INT8),
		INT16 = static_cast<int32_t>(schola::DType::INT16),
		INT32 = static_cast<int32_t>(schola::DType::INT32),
		INT64 = static_cast<int32_t>(schola::DType::INT64),
		FLOAT16 = static_cast<int32_t>(schola::DType::FLOAT16),
		FLOAT64 = static_cast<int32_t>(schola::DType::FLOAT64),
		BOOL = static_cast<int32_t>(schola::DType::BOOL),
	};

	/** Stores one bound per side; existing Box conversion broadcasts over the shape. */
	static godot::Ref<ScholaBoxSpace> box(const godot::PackedInt32Array &p_shape, double p_low, double p_high, int32_t p_dtype = FLOAT32);
	/** Empty bounds are unbounded; singleton bounds broadcast; longer bounds are per element. */
	static godot::Ref<ScholaBoxSpace> box_bounds(const godot::PackedInt32Array &p_shape, const godot::PackedFloat32Array &p_low = {}, const godot::PackedFloat32Array &p_high = {}, int32_t p_dtype = FLOAT32);
	static godot::Ref<ScholaDiscreteSpace> discrete(int32_t p_n);
	static godot::Ref<ScholaMultiDiscreteSpace> multi_discrete(const godot::PackedInt32Array &p_nvec);
	static godot::Ref<ScholaMultiBinarySpace> multi_binary(int32_t p_n);
	/** Child resources remain shared, matching direct ScholaDictSpace assignments. */
	static godot::Ref<ScholaDictSpace> dict(const godot::Dictionary &p_spaces);

protected:
	static void _bind_methods();
};

VARIANT_ENUM_CAST(ScholaSpaces::DType)
