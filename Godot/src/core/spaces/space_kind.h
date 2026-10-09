// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

namespace schola {

// Identifies which alternative a Space or Point holds.
enum class SpaceKind {
	BOX,
	DISCRETE,
	MULTI_DISCRETE,
	MULTI_BINARY,
	DICT,
};

// Element type of Box values. Only float32 is currently supported.
enum class DType { FLOAT32 };

} // namespace schola
