// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/adapters/observation_adapter.h"
#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

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
 * @brief Combines a fixed-length observation history into one observation.
 * Index 0 holds the newest observation. The highest index holds the oldest slot.
 */
class Stacker : public ObservationAdapter {
public:
	/**
	 * @brief Creates a stacker with the given history settings.
	 * @param[in] p_settings History length and default point, validated by configure().
	 */
	explicit Stacker(StackerSettings p_settings);

	/** @return Number of real observations in the history, from 0 to stack_size. */
	int32_t get_num_valid() const;

	/** @return The history length and default-point settings. */
	const StackerSettings &get_settings() const;

	/**
	 * @brief Validates the settings, builds the stacked space, and resets history on success.
	 * @param[in] p_input_space Space of the unstacked observations.
	 * @param[out] r_output_space Space of the stacked observations.
	 * @return OK on success, or an error describing the invalid settings or space.
	 */
	Status configure(const Space &p_input_space, Space &r_output_space) override;

	/**
	 * @brief Adds p_input as the newest observation, dropping the oldest, and fills r_output with the stack.
	 * An invalid p_input leaves the history unchanged.
	 *
	 * @param[in] p_input New observation in the configured input space.
	 * @param[out] r_output Stacked observation in newest-first order.
	 * @return OK on success, INVALID_ARGUMENT for an incompatible input, or
	 * FAILED_PRECONDITION if the stacker needs successful configuration.
	 */
	Status adapt(const Point &p_input, Point &r_output) override;

	/** @brief Fills every history slot with the default point. */
	void reset() override;

protected:
	/**
	 * @brief Builds the stacked space for the given input space.
	 * @param[in] p_unstacked_space Space of a single observation.
	 * @param[out] r_stacked_space Space of the combined history.
	 * @return OK on success, or an error describing an unsupported space or invalid settings.
	 */
	virtual Status make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const = 0;

	/**
	 * @brief Combines the history into a stacked point.
	 * @param[in] p_history The stack_size points from newest to oldest, including default padding.
	 * @param[out] r_stacked Point in the configured stacked space.
	 */
	virtual void make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const = 0;

private:
	StackerSettings settings;
	std::optional<Space> unstacked_space;
	std::deque<Point> history;
	int32_t num_valid = 0;
};

/** @brief Settings for stacking Box observations. */
struct BoxStackerSettings {
	/** @brief History length and default-point settings. */
	StackerSettings stacker;
	/**
	 * @brief Axis for the history. Valid indices are [0, rank] for insertion and [0, rank) for
	 * expansion. Configuration returns INVALID_ARGUMENT for an out-of-range index.
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
 * @brief Combines Box observations along the configured axis in row-major order.
 * The bounds follow the same layout as the values, and the input dtype is preserved.
 */
class BoxStacker : public Stacker {
public:
	/**
	 * @brief Creates a Box stacker.
	 * @param[in] p_settings History and dimension settings, validated by configure().
	 */
	explicit BoxStacker(BoxStackerSettings p_settings);

	/** @return The history and dimension settings. */
	const BoxStackerSettings &get_box_settings() const;

protected:
	Status make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const override;
	void make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const override;

private:
	BoxStackerSettings box_settings;
	mutable size_t values_per_block = 0;
};

/**
 * @brief Combines observations into a Dict with one suffix per history slot.
 * A Dict entry named `key` becomes `key_0` through `key_<stack_size - 1>`. Other inputs use
 * `Point_0` through `Point_<stack_size - 1>`. Output entries are sorted lexicographically by key.
 */
class DictStacker : public Stacker {
public:
	/**
	 * @brief Creates a Dict stacker.
	 * @param[in] p_settings History length and default point, validated by configure().
	 */
	explicit DictStacker(StackerSettings p_settings);

protected:
	Status make_stacked_space(const Space &p_unstacked_space, Space &r_stacked_space) const override;
	void make_stacked_point(const std::deque<Point> &p_history, Point &r_stacked) const override;

private:
	struct OutputEntry {
		std::string key;
		size_t history_slot;
		size_t input_entry;
	};
	mutable std::vector<OutputEntry> output_layout;
};

} // namespace schola
