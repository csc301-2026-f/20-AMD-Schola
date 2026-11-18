# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
class_name ScholaComponentSpace
extends RefCounted

## Compare generated spaces without expanding image-sized broadcast bounds.
static func box(shape: PackedInt32Array, low: PackedFloat32Array, high: PackedFloat32Array) -> ScholaBoxSpace:
	var result := ScholaBoxSpace.new()
	result.shape = shape
	result.low = low
	result.high = high
	return result

static func matches(actual: ScholaSpace, expected: ScholaSpace) -> bool:
	if actual is ScholaBoxSpace and expected is ScholaBoxSpace:
		if actual.shape != expected.shape or actual.dtype != expected.dtype:
			return false
		var count := 1
		for dimension in expected.shape:
			count *= dimension
		return _bounds_equal(actual.low, expected.low, count) and _bounds_equal(actual.high, expected.high, count)
	if actual is ScholaMultiDiscreteSpace and expected is ScholaMultiDiscreteSpace:
		return actual.nvec == expected.nvec
	return false

## A finite determinant alone does not guarantee float32 normalization is safe.
static func is_usable_basis(value: Basis) -> bool:
	if not is_finite(value.determinant()) or value.determinant() == 0:
		return false
	for axis in 3:
		var length := value[axis].length()
		if not is_finite(length) or length == 0:
			return false
	return true

static func _bounds_equal(actual: PackedFloat32Array, expected: PackedFloat32Array, count: int) -> bool:
	if actual.size() not in [1, count] or expected.size() not in [1, count]:
		return false
	if actual == expected:
		return true
	if actual.size() == 1:
		for value in expected:
			if value != actual[0]:
				return false
		return true
	if expected.size() == 1:
		for value in actual:
			if value != expected[0]:
				return false
		return true
	return false
