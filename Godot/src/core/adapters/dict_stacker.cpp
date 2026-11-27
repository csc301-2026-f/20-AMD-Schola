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
	std::vector<OutputEntry> layout;
	const auto *input_dict = p_unstacked_space.get_if<DictSpace>();

	for (int32_t i = 0; i < get_settings().stack_size; ++i) {
		std::string suffix = "_" + std::to_string(i);
		if (!input_dict) {
			stacked.entries.emplace_back("Point" + suffix, p_unstacked_space);
			layout.push_back({ "Point" + suffix, static_cast<size_t>(i), 0 });
			continue;
		}

		for (size_t entry = 0; entry < input_dict->entries.size(); ++entry) {
			const auto &[key, space] = input_dict->entries[entry];
			stacked.entries.emplace_back(key + suffix, space);
			layout.push_back({ key + suffix, static_cast<size_t>(i), entry });
		}
	}

	r_stacked_space = Space(std::move(stacked));
	Status status = r_stacked_space.check_definition();
	if (status.is_ok()) {
		// Key names and their lexicographic order are fixed until reconfiguration.
		std::sort(layout.begin(), layout.end(), [](const auto &p_a, const auto &p_b) { return p_a.key < p_b.key; });
		output_layout = std::move(layout);
	}
	return status;
}

void DictStacker::make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const {
	DictPoint stacked;

	stacked.entries.reserve(output_layout.size());
	for (const auto &entry : output_layout) {
		const Point &point = p_history[entry.history_slot];
		const auto *dict = point.get_if<DictPoint>();
		stacked.entries.emplace_back(entry.key, dict ? dict->entries[entry.input_entry].second : point);
	}

	r_stacked = Point(std::move(stacked));
}

} // namespace schola
