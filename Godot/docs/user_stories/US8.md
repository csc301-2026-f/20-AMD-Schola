# US8: Compose agents from reusable sensors and actuators

- **Owner:** Guneev
- **Status:** Complete on main
- **Priority:** MVP (highest priority)
- **Last updated:** Nov. 25, 2026

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

[PR #51](https://github.com/csc301-2026-f/20-AMD-Schola/pull/51) merged and adds native sensor and actuator base nodes, deterministic scene-tree composition, reusable components, diagnostics and a playground. The [US13 RaceTrack example](US13.md), merged in [PR #50](https://github.com/csc301-2026-f/20-AMD-Schola/pull/50), composes the ray-cast sensor with three add-on components it introduced: `ScholaPathSensor3D`, `ScholaVelocitySensor3D` and `ScholaVehicleActuator3D`. [PR #91](https://github.com/csc301-2026-f/20-AMD-Schola/pull/91) sets up the ray sensor's physics query once per observation instead of once per ray, and [PR #89](https://github.com/csc301-2026-f/20-AMD-Schola/pull/89) makes the teleport actuator say which directions to enable.

## Scope limits

- The original US8 baseline excluded camera capture. Main also includes real and fake camera sensors; rendering configuration and validation are documented with US11.
- This story does not introduce Godot-only observation or action semantics.

## Implementation

See [the component API guide](../us8_components.md) for native base nodes,
GDScript implementations, ordering, direct-hook precedence, and Unreal mapping.
Behavior is covered by `tests/integration/components_test.gd`.
