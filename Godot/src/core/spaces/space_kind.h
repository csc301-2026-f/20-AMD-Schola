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

// Box element type, in Proto/DType.proto order. Values are always stored as float, as on the wire.
enum class DType {
	FLOAT32,
	UINT8,
	UINT16,
	UINT32,
	UINT64,
	INT8,
	INT16,
	INT32,
	INT64,
	FLOAT16,
	FLOAT64,
	BOOL,
};

} // namespace schola
