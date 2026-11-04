# Remaining work and future opportunities

This document records work that is not represented as a separate active user story. Items here are not commitments. They should become stories only when a concrete user outcome, AMD priority, and maintainable cross-engine design justify the additional scope.

## Required integration and release work

These tasks complete or validate existing stories rather than introducing new product capabilities:

- Complete the production end-to-end path across the Godot environment, lifecycle, gRPC transport, Python client, and ONNX inference components.
- Test installation, training, export, inference, and packaging from a clean checkout.
- Document the approved move from the specification's preferred C# implementation to the C++ GDExtension architecture.
- Maintain setup, usage, architecture, troubleshooting, and packaging documentation.
- Verify error behavior and Inspector configuration warnings consistently across Godot-facing APIs.
- Confirm that exported games can omit training and transport dependencies.
- Do not replace components in the frozen D1 or D2 demos; use a new current example for production integration.

## Possible cross-engine follow-ups

These capabilities already exist in Unreal Schola or have a clear equivalent, but are not currently proposed as course commitments:

- **Parallel headless training:** Run multiple isolated environment instances in one Godot process using its supported headless mode. Validate stable environment IDs, isolated episode state, session-wide failure behavior, configuration documentation, and a simple throughput comparison. Camera observations would require a supported renderer or a clear incompatibility error. Distributed training across machines or processes remains out of scope.
- Additional actuator nodes, including rotation and teleport actuators.
- Additional non-visual sensors after the US8 composition contract is stable.
- Text spaces and points if the shared protocol and Python consumers require them.
- Pipelined inference, but only if profiling demonstrates that synchronous inference causes unacceptable frame stalls.
- Further observation adapters beyond Box and Dict stacking.
- Additional manual-connector diagnostics built on US9.
- Broader packaged-platform and renderer coverage for camera observations.

## Framework and tooling breadth

Unreal Schola exposes extensive training configuration and process-management utilities. Port these only when they improve the Godot workflow without duplicating the Python CLI:

- Stable-Baselines3 and RLlib algorithm, logging, checkpoint, resume, resource, and network settings in the Inspector.
- Launching, monitoring, and terminating Python training processes from Godot.
- Custom editor docks or dashboards beyond normal nodes, resources, signals, and Inspector warnings.
- Additional connector variants not required by the production Python workflow.

## Specialized Unreal integrations not planned for direct porting

These modules depend on Unreal-specific systems or represent major separate product areas. They require an independently justified Godot design rather than class-for-class porting:

- Unreal StateTree integration.
- Unreal Neural Network Engine integration.
- Imitation learning and Minari data collection.
- Unreal-specific Blueprint and editor utility libraries.

## Decision rule

Before promoting an item into a user story, confirm that:

1. It solves a concrete Godot user problem.
2. Its Schola semantics can be maintained across engines, even if its interface is engine-native.
3. It cannot be completed more appropriately as a task within an existing story.
4. Its maintenance cost is acceptable to AMD after the course.
5. It does not delay the required end-to-end training and inference workflow.
