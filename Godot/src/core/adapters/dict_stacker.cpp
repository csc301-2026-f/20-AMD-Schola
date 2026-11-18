// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
#include "core/adapters/stacker.h"

#include "core/adapters/observation_adapter.h"
#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include <algorithm>
#include <deque>
#include <optional>
#include <utility>

namespace schola {

DictStacker::DictStacker(StackerSettings p_settings) :
		Stacker(std::move(p_settings)) {}

Status DictStacker::make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const {
	DictSpace stacked;
	const auto *input_dict = p_unstacked_space.get_if<DictSpace>();

	for (int32_t i = 0; i < get_settings().stack_size; ++i) {
		std::string suffix = "_" + std::to_string(i);
		if (!input_dict) {
			stacked.entries.emplace_back("Point" + suffix, p_unstacked_space);
			continue;
		}

		for (const auto &[key, space] : input_dict->entries) {
			stacked.entries.emplace_back(key + suffix, space);
		}
	}

	r_stacked_space = Space(std::move(stacked));
	return r_stacked_space.check_definition();
}

void DictStacker::make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const {
	DictPoint stacked;

	size_t slot = 0;
	for (const Point &point : p_history) {
		std::string suffix = "_" + std::to_string(slot);

		if (const auto *dict = point.get_if<DictPoint>()) {
			for (const auto &[key, value] : dict->entries) {
				stacked.entries.emplace_back(key + suffix, value);
			}
		} else {
			stacked.entries.emplace_back("Point" + suffix, point);
		}
		++slot;
	}

	std::sort(stacked.entries.begin(), stacked.entries.end(),
			[](auto &a, auto &b) { return a.first < b.first; });

	r_stacked = Point(std::move(stacked));
}

} // namespace schola
