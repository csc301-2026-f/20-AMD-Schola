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
	static constexpr int32_t MAX_STATE_SEQUENCE_LENGTH = 65536;

	OnnxPolicy();
	~OnnxPolicy() override;

	Status load_model(const uint8_t *p_data, size_t p_size, const std::string &p_model_name);
	void unload_model();
	bool is_loaded() const;
	std::vector<int64_t> get_state_sequence_lengths() const;
	std::vector<std::string> get_sequence_warnings() const;
	const std::vector<std::string> &get_input_names() const;
	const std::vector<std::string> &get_output_names() const;

	Status init(const InteractionDefinition &p_definition) override;
	Status create_initial_state(std::unique_ptr<PolicyState> &r_state) const override;
	Status think(const Point &p_observation, PolicyState &p_state, Point &r_action) override;
	bool is_recurrent() const override;

	bool is_ready() const;

private:
	struct Impl;
	std::unique_ptr<Impl> impl;
};

} // namespace schola
