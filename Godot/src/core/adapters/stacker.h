// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/adapters/observation_adapter.h"
#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include <cstdint>
#include <deque>
#include <optional>

namespace schola {

/** @brief Settings shared by every stacker. */
struct StackerSettings {
	/** @brief Number of observations kept in the history. Must be at least 1. */
	int32_t stack_size = 4;
	/**
	 * @brief Fills history slots that have no observation yet. Must fit the unstacked space. When empty, the
	 * unstacked space's make_point() is used.
	 */
	std::optional<Point> default_point;
};

/**
 * @brief Keeps the last stack_size observations and outputs them as one stacked observation. Index 0 is the
 * newest observation and the highest index is the oldest, matching Unreal Schola's UStackerBase.
 */
class Stacker : public ObservationAdapter {
public:
	explicit Stacker(StackerSettings p_settings);

	/** @brief Checks stack_size and default_point, then builds the stacked space. Also resets the history. */
	Status configure(const Space &p_input_space, Space &r_output_space) override;
	/** @brief Fills every history slot with the default point. */
	void reset() override;
	/**
	 * @brief Adds p_input as the newest observation, dropping the oldest, and fills r_output with the stack.
	 * An invalid p_input leaves the history unchanged.
	 */
	Status adapt(const Point &p_input, Point &r_output) override;

	/** @return Number of real observations in the history, from 0 to stack_size. */
	int32_t get_num_valid() const;
	const StackerSettings &get_settings() const;

protected:
	/** @brief Checks that p_unstacked_space is a kind this stacker supports and fills r_stacked_space. */
	virtual Status make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const = 0;
	/** @brief Fills r_stacked with the current history, which holds stack_size points from newest to oldest. */
	virtual void make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const = 0;

private:
	StackerSettings settings;
	std::optional<Space> unstacked_space;
	std::deque<Point> history;
	int32_t num_valid = 0;
};

/** @brief Settings for stacking Box observations. */
struct BoxStackerSettings {
	StackerSettings stacker;
	/**
	 * @brief The dimension that holds the history, in [0, rank] when adding a new dimension and in [0, rank)
	 * when expanding one. Unreal Schola clamps an out-of-range index; Godot reports it instead.
	 */
	int32_t stack_dimension = 0;
	/**
	 * @brief If true, inserts a new dimension of size stack_size at stack_dimension, so (a, b) with index 0
	 * becomes (stack_size, a, b). If false, multiplies the existing dimension by stack_size, so (a, b)
	 * with index 1 becomes (a, b * stack_size).
	 */
	bool add_new_dimension = true;
};

/**
 * @brief Stacks Box observations into one Box, matching Unreal Schola's UBoxStacker. Values stay row-major,
 * low and high are repeated for each history slot, and dtype is unchanged.
 */
class BoxStacker : public Stacker {
public:
	explicit BoxStacker(BoxStackerSettings p_settings);

	const BoxStackerSettings &get_box_settings() const;

protected:
	Status make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const override;
	void make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const override;

private:
	BoxStackerSettings box_settings;
};

/**
 * @brief Stacks observations into one Dict, matching Unreal Schola's UDictStacker. A Dict entry "key" becomes
 * "key_0" (newest) through "key_<stack_size - 1>" (oldest). Any other space becomes "Point_0" through
 * "Point_<stack_size - 1>". Entries are then sorted by key like every DictSpace.
 */
class DictStacker : public Stacker {
public:
	explicit DictStacker(StackerSettings p_settings);

protected:
	Status make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const override;
	void make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const override;
};

} // namespace schola
