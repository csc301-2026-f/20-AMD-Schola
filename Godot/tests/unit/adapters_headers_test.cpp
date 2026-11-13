// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Compiles the public observation adapter headers together. Behavioral tests are added with the
// implementation.

#include "core/adapters/observation_adapter.h"
#include "core/adapters/stacker.h"

#include <type_traits>
#include <utility>

namespace schola {

static_assert(std::is_abstract_v<ObservationAdapter>);
static_assert(std::is_abstract_v<Stacker>);
static_assert(std::is_base_of_v<ObservationAdapter, Stacker>);
static_assert(std::is_base_of_v<Stacker, BoxStacker>);
static_assert(std::is_base_of_v<Stacker, DictStacker>);
static_assert(!std::is_abstract_v<BoxStacker> && !std::is_abstract_v<DictStacker>);
static_assert(!std::is_copy_constructible_v<ObservationAdapterChain>);
static_assert(std::is_move_constructible_v<ObservationAdapterChain>);
static_assert(std::is_same_v<decltype(std::declval<ObservationAdapter &>().configure(std::declval<const Space &>(), std::declval<Space &>())), Status>);
static_assert(std::is_same_v<decltype(std::declval<ObservationAdapter &>().adapt(std::declval<const Point &>(), std::declval<Point &>())), Status>);

} // namespace schola
