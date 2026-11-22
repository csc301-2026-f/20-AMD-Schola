// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
#include "core/adapters/stacker.h"

#include "core/adapters/observation_adapter.h"
#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include <cstddef>
#include <cstdint>
#include <deque>
#include <utility>

namespace schola {

namespace {

template <typename ValuesAt>
void append_stack(std::vector<float> &r_values, std::size_t p_input_size,
		std::size_t p_block_size, std::size_t p_stack_size, ValuesAt p_values_at) {
	r_values.reserve(p_input_size * p_stack_size);
	for (std::size_t offset = 0; offset < p_input_size; offset += p_block_size) {
		for (std::size_t slot = 0; slot < p_stack_size; ++slot) {
			const auto first = p_values_at(slot).begin() + offset;
			r_values.insert(r_values.end(), first, first + p_block_size);
		}
	}
}

} // namespace

BoxStacker::BoxStacker(BoxStackerSettings p_settings) :
		Stacker(p_settings.stacker),
		box_settings(std::move(p_settings)) {}

const BoxStackerSettings &BoxStacker::get_box_settings() const {
	return box_settings;
}

Status BoxStacker::make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const {
	const auto *input_box = p_unstacked_space.get_if<BoxSpace>();
	if (!input_box) {
		return Status::error(StatusCode::INVALID_ARGUMENT,
				"BoxStacker requires a Box input space");
	}

	const int32_t axis = box_settings.stack_dimension;
	const bool insert_axis = box_settings.add_new_dimension;
	const auto rank = input_box->shape.size();

	if (axis < 0) {
		return Status::error(StatusCode::INVALID_ARGUMENT,
				"stack_dimension must be nonnegative");
	}

	const auto index = static_cast<std::size_t>(axis);
	if (index > rank || (index == rank && !insert_axis)) {
		return Status::error(StatusCode::INVALID_ARGUMENT,
				"stack_dimension is out of range for the input Box shape");
	}

	BoxSpace stacked;
	stacked.shape = input_box->shape;
	const int32_t stack_size = get_settings().stack_size;

	if (insert_axis) {
		stacked.shape.insert(stacked.shape.begin() + axis, stack_size);
	} else {
		const int64_t expanded = static_cast<int64_t>(stacked.shape[index]) * stack_size;
		if (expanded > INT32_MAX) {
			return Status::error(StatusCode::INVALID_ARGUMENT,
					"expanded Box dimension exceeds int32_t range");
		}
		stacked.shape[index] = static_cast<int32_t>(expanded);
	}

	// A row-major block spans the axes at and after the stacking axis.
	std::size_t block_size = 1;
	for (std::size_t i = index; i < rank; ++i) {
		block_size *= input_box->shape[i];
	}
	const auto slots = static_cast<std::size_t>(stack_size);
	// Space definitions limit the total element count, not just each dimension.
	if (input_box->low.size() > static_cast<std::size_t>(INT32_MAX) / slots ||
			input_box->low.size() > stacked.low.max_size() / slots) {
		return Status::error(StatusCode::INVALID_ARGUMENT,
				"stacked Box contains too many values");
	}
	stacked.dtype = input_box->dtype;
	append_stack(stacked.low, input_box->low.size(), block_size, slots,
			[&](std::size_t) -> const auto & { return input_box->low; });
	append_stack(stacked.high, input_box->high.size(), block_size, slots,
			[&](std::size_t) -> const auto & { return input_box->high; });

	Space output(std::move(stacked));
	Status status = output.check_definition();
	if (status.is_ok()) {
		values_per_block = block_size;
		r_stacked_space = std::move(output);
	}
	return status;
}

void BoxStacker::make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const {
	BoxPoint stacked;
	append_stack(stacked.values, p_history.front().get_if<BoxPoint>()->values.size(),
			values_per_block, p_history.size(),
			[&](std::size_t slot) -> const auto & { return p_history[slot].get_if<BoxPoint>()->values; });
	r_stacked = Point(std::move(stacked));
}

} // namespace schola
