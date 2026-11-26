# US2: Declare observation and action spaces

- **Owner:** Jimmy
- **Status:** Complete on main
- **Last updated:** Nov. 25, 2026

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
- Protobuf conversion code and round-trip tests exist for spaces, points, interaction definitions, and agent states. SCons supplies generated bindings and includes these tests in `transport_tests`, which CI runs. The production scene connector subsequently merged in [PR #59](https://github.com/csc301-2026-f/20-AMD-Schola/pull/59); see [US3](US3.md) for the trainer-run evidence.
- Validation fixes since then: Box rejects a low of inf or a high of -inf ([PR #78](https://github.com/csc301-2026-f/20-AMD-Schola/pull/78)) and finite float16 bounds that overflow in Python ([PR #85](https://github.com/csc301-2026-f/20-AMD-Schola/pull/85)); MultiBinary values other than 0 or 1 get one consistent error ([PR #89](https://github.com/csc301-2026-f/20-AMD-Schola/pull/89)); Box errors print the exact value, such as `1.0000001` instead of `1` ([PR #90](https://github.com/csc301-2026-f/20-AMD-Schola/pull/90)); and the Discrete and MultiBinary Inspector ranges start at 0 so they show the unconfigured value, which validation still rejects ([PR #92](https://github.com/csc301-2026-f/20-AMD-Schola/pull/92)).
