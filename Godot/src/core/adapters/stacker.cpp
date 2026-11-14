// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "stacker.h"

#include "core/adapters/observation_adapter.h"
#include "core/adapters/stacker.h"
#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include <cstdint>
#include <deque>
#include <optional>

namespace schola {

Stacker::Stacker(StackerSettings p_settings) : settings(p_settings) {}

int32_t Stacker::get_num_valid() const {
	return num_valid;
}

const StackerSettings &Stacker::get_settings() const {
	return settings;
}

Status Stacker::configure(const Space &p_input_space, Space &r_output_space) {
	unstacked_space.reset();
	history.clear();
	num_valid = 0;

	if (settings.stack_size < 1) {
		return Status::error(StatusCode::INVALID_ARGUMENT,
				"stack_size must be at least 1");
	}

	Status status = p_input_space.check_definition();
	if (!status.is_ok()) return status;

	if (settings.default_point) {
		status = p_input_space.validate(*settings.default_point);
		if (!status.is_ok()) {
			return Status::error(StatusCode::INVALID_ARGUMENT,
					"default_point: " + status.get_message());
		}
	}

	Space stacked_space;
	status = make_stacked_space(p_input_space, stacked_space);
	if (!status.is_ok()) return status;

	unstacked_space = p_input_space;
	reset();
	r_output_space = std::move(stacked_space);
	return status;
}

Status Stacker::adapt(const Point &p_input, Point &r_output) {
	if (!unstacked_space) {
		return Status::error(StatusCode::FAILED_PRECONDITION,
				"Stacker must be configured before adapting observations");
	}

	Status status = unstacked_space->validate(p_input);
	if (!status.is_ok()) return status;

	if (num_valid < settings.stack_size) {
		++num_valid;
	}

	history.push_front(p_input);
	history.pop_back();
	make_stacked_point(history, r_output);
	return status;
}

void Stacker::reset() {
	num_valid = 0;
	history.clear();

	if (!unstacked_space) return;

	Point new_location = settings.default_point ? *settings.default_point : unstacked_space->make_point();
	history.assign(settings.stack_size, new_location);
}

} // namespace schola
