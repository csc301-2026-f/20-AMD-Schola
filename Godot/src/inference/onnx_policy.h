// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/policy/policy.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace schola {

class OnnxPolicy final : public Policy {
public:
	OnnxPolicy();
	~OnnxPolicy() override;

	Status load_model(const uint8_t *p_data, size_t p_size, const std::string &p_model_name);
	Status set_max_state_sequence_length(int32_t p_length);
	int32_t get_max_state_sequence_length() const;
	const std::vector<std::string> &get_input_names() const;
	const std::vector<std::string> &get_output_names() const;

	Status init(const InteractionDefinition &p_definition) override;
	Status create_initial_state(std::unique_ptr<PolicyState> &r_state) const override;
	Status think(const Point &p_observation, PolicyState &p_state, Point &r_action) override;
	Status batched_think(const std::vector<const Point *> &p_observations, const std::vector<PolicyState *> &p_states, const std::vector<Point *> &r_actions) override;
	bool is_recurrent() const override;

	bool is_ready() const;

private:
	struct Impl;
	std::unique_ptr<Impl> impl;
};

} // namespace schola
