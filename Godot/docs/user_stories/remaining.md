# Maintenance and future opportunities

This document records work that is not represented as a separate active user story. Items here are not commitments. They should become stories only when a concrete user outcome, AMD priority, and maintainable cross-engine design justify the additional scope.

## Maintenance of the delivered workflows

RaceTrack, the camera pipeline, the Python connector, and simultaneous-agent training are merged. Existing story verification is recorded in the [story index](README.md) and [verification record](../verification.md). Future maintenance should:

- Keep source setup, installation, training, export, inference, and troubleshooting instructions aligned with the supported dependencies.
- Run the appropriate native and Godot integration suites after changes; preserve the required PR checks and platform package installation checks.
- Repeat real-trainer smoke checks when the protocol, Python wrappers, spaces, or dependency versions change. Protocol fixtures and short PPO updates check compatibility; learned-policy quality is evaluated separately in RaceTrack.
- Preserve the runtime/training extension split and verify exported games on their target platform. Windows export evidence and clean-project package loading have different scopes.
- Maintain the dev and release distribution workflows, license notices, dependency provenance, and source revision records.
- Preserve submitted D1-D3 artifacts. Put current examples and future improvements under `Godot/examples/` and `Godot/docs/`.

## Specific extension and validation opportunities

- **Camera learning benchmark:** Train and evaluate a vision policy beyond the existing camera smoke/export checks. Broaden real-renderer, platform, and exported-game coverage. Latest-completed-frame capture remains the delivered contract.
- **Recurrent trainer fixture:** Add an end-to-end trainer-exported sequence-dimension model when the shared old-stack RLlib export path supports it. The metadata reader, synthetic sequence fixture, and ordinary recurrent-model paths already have tests; see [US14](US14.md).
- **Stacking breadth:** The live trainer check covers a 3-frame Box stack. Preserve the core/integration coverage for Dict stacking, padding, ordering, independent histories, and reset behavior; add representative real-trainer cases when those workflows change.
- **Multi-agent benchmarking:** The number-line example trains distinct policies and RaceTrack supplies shared-policy scenes. Longer cooperative/competitive benchmarks, saved multi-agent RaceTrack policies, and broader dynamic-population trainer runs are additional evidence, rather than missing baseline multi-agent functionality.

## Possible cross-engine follow-ups

These capabilities already exist in Unreal Schola or have a clear equivalent, but are not currently proposed as course commitments:

- **Parallel headless training:** Run multiple isolated environment instances in one Godot process using its supported headless mode. Validate stable environment IDs, isolated episode state, session-wide failure behavior, configuration documentation, and a simple throughput comparison. Camera observations would require a supported renderer or a clear incompatibility error. Distributed training across machines or processes remains out of scope.
- Additional actuator types beyond the movement, rotation, teleport, and vehicle components on main.
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
