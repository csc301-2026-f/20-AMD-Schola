# US2: Declare observation and action spaces

- **Owner:** Jimmy
- **Status:** Complete on main
- **Last updated:** November 26, 2026

## Story

As a Godot developer, I want to define observation and action spaces using reusable types so that Schola can validate and communicate the agent's available inputs and outputs.

## Acceptance criteria

- The core supports Box, Discrete, MultiDiscrete, and MultiBinary spaces and their corresponding point values.
- Spaces expose their shape, bounds, and data type where applicable.
- An omitted Box bound represents an unbounded dimension rather than zero.
- An observation or action that does not match its declared space is rejected with a useful error.
- Space definitions can be translated to the representation expected by the existing Schola Python package.
- Round-trip tests serialize and deserialize spaces, points, interaction definitions, and agent states without changing their values.

## Progress

- Space and point resources landed in [PR #30](https://github.com/csc301-2026-f/20-AMD-Schola/pull/30), followed by final validation and consistency fixes in [PR #36](https://github.com/csc301-2026-f/20-AMD-Schola/pull/36) ([`f5bfd2b`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/f5bfd2b)). The transport path and its tests landed in [PR #47](https://github.com/csc301-2026-f/20-AMD-Schola/pull/47). Programmatic space definitions are tracked in [US15](US15.md).
- The current union-type approach was compared with the alternative proposed at the Oct. 23 partner meeting.
- The team confirmed the union-type approach because it avoids unnecessary complexity.
- Core spaces, points, and Inspector resources are implemented and merged in #30, including Box, Discrete, MultiDiscrete, MultiBinary, and Dict.
- Passing core and Godot integration tests cover definitions, shape and bounds validation, unbounded Box dimensions, invalid values, and nested Dict resources.
- Protobuf conversion code and round-trip tests exist for spaces, points, interaction definitions, and agent states. SCons supplies generated bindings and includes these tests in `transport_tests`, which CI runs. The production scene connector subsequently merged in [PR #59](https://github.com/csc301-2026-f/20-AMD-Schola/pull/59); see [US3](US3.md) for supported-trainer evidence.

## Current integration evidence

PRs #78 and #85 reject impossible infinite bounds and finite float16 bounds that overflow in Python. PRs #89 and #90 improve validation diagnostics. Dict spaces are supported alongside the scalar/array space families.

See the [verification record](../verification.md) for the checked main revision, passing CI jobs, and local verification.
