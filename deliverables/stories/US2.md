# US2: Declare observation and action spaces

- **Owner:** Jimmy
- **Status:** Implemented; final integration work remains
- **Last updated:** Oct. 30, 2026

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

- The current union-type approach was compared with the alternative proposed at the Oct. 23 partner meeting.
- The team confirmed the union-type approach because it avoids unnecessary complexity.
- The core spaces-and-points implementation is complete; remaining work is limited to final integration and edge-case validation.
