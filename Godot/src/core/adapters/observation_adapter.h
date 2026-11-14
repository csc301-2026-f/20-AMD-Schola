// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include <memory>
#include <vector>

namespace schola {

/**
 * @brief Transforms an agent's observations before they reach the trainer or a local policy, such as by
 * stacking recent observations. An adapter can change the observation space, so it reports the space it
 * produces before training or inference begins.
 *
 * An adapter instance holds per-agent episode state, such as observation history. Each agent owns its
 * own instances; agents never share one.
 */
class ObservationAdapter {
public:
	virtual ~ObservationAdapter() = default;

	/**
	 * @brief Configures the adapter and reports the space produced by adapt().
	 *
	 * Call before reset() or adapt(), and again if the input space changes.
	 *
	 * @param[in] p_input_space Space of the incoming observations.
	 * @param[out] r_output_space Space of the adapted observations.
	 * @return OK on success, or INVALID_ARGUMENT naming the incompatible setting.
	 */
	virtual Status configure(const Space &p_input_space, Space &r_output_space) = 0;

	/** @brief Clears episode state. Called at the beginning of every episode. */
	virtual void reset() = 0;

	/**
	 * @brief Transforms one observation.
	 * @param[in] p_input Observation in the configured input space.
	 * @param[out] r_output Adapted observation.
	 * @return OK on success, INVALID_ARGUMENT for an incompatible input, or
	 * FAILED_PRECONDITION if the most recent configure() call failed or configure() has never been called.
	 */
	virtual Status adapt(const Point &p_input, Point &r_output) = 0;
};

// This class might be a little overdone so gonna do this for now.
#if 0

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

#endif

} // namespace schola
