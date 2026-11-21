# US8: Compose agents from reusable sensors and actuators

- **Owner:** Guneev
- **Status:** Complete on main (PR #51)
- **Priority:** MVP (highest priority)
- **Last updated:** Nov. 21, 2026

## Story

As a Godot developer, I want to compose an agent from reusable sensor and actuator nodes so that I can define common observations and actions without implementing every behavior hook from scratch.

## Rationale

Schola for Unreal already represents sensors and actuators as reusable components. Godot should provide the same capability through child nodes, its native mechanism for composing scene behavior. The engines share the sensor and actuator semantics without requiring identical APIs or class structures.

## Acceptance criteria

- Schola defines extensible Godot-facing sensor and actuator base types.
- A `ScholaAgent` discovers its sensor and actuator descendants in deterministic scene-tree order.
- The agent combines their spaces into one interaction definition and combines their values in the same order.
- The initial implementation includes one reusable ray-cast sensor and one reusable movement actuator.
- A developer can implement a custom sensor or actuator in GDScript.
- Invalid spaces, duplicate identifiers, and incorrectly placed components produce Inspector configuration warnings.
- Developers can continue overriding the agent's direct observation and action hooks when reusable components are not appropriate.
- The design documents how its concepts correspond to Unreal Schola's sensor and actuator interfaces.

## Progress

[PR #51](https://github.com/csc301-2026-f/20-AMD-Schola/pull/51) merged on Nov. 18. Main contains native sensor/actuator base nodes, deterministic scene-tree composition, reusable ray-cast and movement components, GDScript extension hooks, configuration diagnostics, and the component playground. Direct agent hooks remain supported.

The PR reports 116 core, 31 inference, 21 transport and 103 Godot integration test cases passing on Linux, plus the playground smoke check. These are recorded PR results, not fresh test runs performed for this status update. Interactive Inspector, other-platform and exported-build checks were not performed in that PR's validation.

Real and fake camera infrastructure is also on main; the remaining camera workflow is tracked under [US11](US11.md). Draft [PR #50](https://github.com/csc301-2026-f/20-AMD-Schola/pull/50) adds RaceTrack-specific use and further reusable components; those additions are not yet merged.

## Scope limits

- The original US8 baseline excluded camera capture. The requested parity extension now adds real and fake camera sensors; rendering configuration and validation are documented with US11.
- This story does not introduce Godot-only observation or action semantics.

## Implementation

See [the component API guide](../us8_components.md) for native base nodes,
GDScript implementations, ordering, direct-hook precedence, and Unreal mapping.
Behavior is covered by `tests/integration/components_test.gd`.
