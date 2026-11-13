// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include <memory>
#include <vector>

namespace schola {

// Transforms an agent's observations before they reach the trainer or a local policy, such as by
// stacking recent observations. An adapter can change the observation space, so it reports the space it
// produces before training or inference begins.
//
// An adapter instance holds per-agent episode state, such as observation history. Each agent owns its
// own instances; agents never share one.
class ObservationAdapter {
public:
	virtual ~ObservationAdapter() = default;

	// Checks the adapter's settings against p_input_space and fills r_output_space with the space that
	// adapt() produces. Called once before reset() or adapt(), and again if the input space changes.
	// Returns INVALID_ARGUMENT, naming the setting, if the settings do not fit p_input_space.
	virtual Status configure(const Space &p_input_space, Space &r_output_space) = 0;

	// Clears episode state. Called at the beginning of every episode.
	virtual void reset() = 0;

	// Transforms one observation from the configured input space into r_output. Returns
	// INVALID_ARGUMENT if p_input does not fit the input space, or FAILED_PRECONDITION if configure()
	// has not succeeded.
	virtual Status adapt(const Point &p_input, Point &r_output) = 0;
};

// An ordered list of adapters applied to one agent's observations. Each adapter's output space is the
// next adapter's input space. An empty chain passes observations through unchanged.
class ObservationAdapterChain {
public:
	ObservationAdapterChain() = default;
	ObservationAdapterChain(const ObservationAdapterChain &) = delete;
	ObservationAdapterChain &operator=(const ObservationAdapterChain &) = delete;
	ObservationAdapterChain(ObservationAdapterChain &&) = default;
	ObservationAdapterChain &operator=(ObservationAdapterChain &&) = default;

	void add(std::unique_ptr<ObservationAdapter> p_adapter);
	bool is_empty() const;

	// Configures each adapter in order and fills r_output_space with the final space. Returns the first
	// failure, prefixed with the adapter's index.
	Status configure(const Space &p_input_space, Space &r_output_space);
	void reset();
	// Runs each adapter in order. Returns the first failure, prefixed with the adapter's index.
	Status adapt(const Point &p_input, Point &r_output);

private:
	std::vector<std::unique_ptr<ObservationAdapter>> adapters;
};

} // namespace schola
