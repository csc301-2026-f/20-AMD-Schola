# Remaining work and future opportunities

This document records work that is not represented as a separate active user story. Items here are not commitments. They should become stories only when a concrete user outcome, AMD priority, and maintainable cross-engine design justify the additional scope.

## Required integration and release work

These tasks complete or validate existing stories rather than introducing new product capabilities:

- Merge the [US13 RaceTrack example](US13.md), which trains through the [US3](US3.md) scene connector merged in PR #59.
- Verify installation, Python training, export, local ONNX inference, and packaging together from a clean checkout. Include the simultaneous-agent training run tracked in [US12](US12.md).
- Document the approved move from the specification's preferred C# implementation to the C++ GDExtension architecture.
- Maintain setup, usage, architecture, troubleshooting, and packaging documentation.
- Verify error behavior and Inspector configuration warnings consistently across Godot-facing APIs.
- Confirm that exported games can omit training and transport dependencies.
- Do not replace components in the frozen D1 or D2 demos; use a new current example for production integration.

## Possible cross-engine follow-ups

These capabilities already exist in Unreal Schola or have a clear equivalent, but are not currently proposed as course commitments:

- **Parallel headless training:** Run multiple isolated environment instances in one Godot process using its supported headless mode. Validate stable environment IDs, isolated episode state, session-wide failure behavior, configuration documentation, and a simple throughput comparison. Camera observations would require a supported renderer or a clear incompatibility error. Distributed training across machines or processes remains out of scope.
- Additional actuator types beyond the movement, rotation and teleport nodes on main.
- Additional non-visual sensors beyond the merged US8 composition contract.
- Text spaces and points if the shared protocol and Python consumers require them.
- Pipelined inference, but only if profiling demonstrates that synchronous inference causes unacceptable frame stalls.
- Further observation adapters beyond Box and Dict stacking.
- Additional manual-connector diagnostics built on US9.
- Broader packaged-platform and renderer coverage for camera observations.
- **Optional render-synchronized lifecycle:** Preserve latest-completed-frame capture as a selectable mode, and add a mode that applies actions or resets, advances a defined amount of simulation, waits for the required camera viewports to render, and then collects observations and matching reward/state before replying. Define terminal/autoreset handling, frame freshness, and unavailable-render behavior across training and inference. This is deferred beyond US11 and requires its own user story.

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
