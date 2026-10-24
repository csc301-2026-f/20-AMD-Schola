# D2 Individual Contributions

## Shahyar Anfaz - Episode lifecycle and build foundation

- Built the C++ GDExtension foundation, including SCons targets, pinned submodules and dependencies, runtime and training add-ons, GitHub Actions, Catch2, GdUnit4, and contributor documentation (#1, #5).
- Defined the shared `Status` and identifier types and the US4 episode-lifecycle API (#6, #8).
- Implemented and tested lifecycle reset, step, terminal, truncation, autoreset, response validation, and step counting, then brought the implementation onto the D2 release branch (#22).
- Assembled the D2 release branch, separated the D1 and D2 demos, reconciled integration changes, and maintained the release documentation.

## Guneev Pannu - Environment coordination and project management

- Implemented and tested `EnvironmentCoordinator`, including stable environment ordering, routed resets and steps, autoreset delegation, close behavior, and failure handling.
- Strengthened lifecycle validation for malformed agent responses and refactored completion checks.
- Added optional staged C++ formatting hooks and documented their setup.
- Coordinated team scheduling, task ownership, and D2 delivery work.

## Sanjay Ram - Connector lifecycle and meeting management

- Defined the US3 connector, training-message, gRPC boundary, and training-side Godot APIs (#12).
- Implemented the engine-independent connector loop and 18 focused tests covering request order, routing, timeout, disconnect, backend failure, close, and stop behavior (#20).
- Built the demo's localhost JSON connector, separated socket handling from the runner, updated the Python client, and documented how the temporary protocol maps to the planned gRPC integration (#20).
- Recorded TA meeting decisions and maintained team meeting records (#3).

## Vansh Sehrawat - Godot configuration and partner liaison

- Defined the US5 Godot binding contract (#9), compatible with US1, US2, US4, and US7: `ScholaAgent`/`ScholaEnvironment` nodes, Inspector space resources, configuration diagnostics, and the Variant-to-core conversion boundary.
- Implemented and integrated the native US5 bindings into the D2 grid-world demo (#26): class registration, agent/environment Inspector properties and validation, descendant-agent discovery, native demo nodes, and a headless smoke test.
- Worked with Jimmy (US2 developer) to plan and review the space-resource API, ensuring it supports US5 Inspector configuration and core-value conversion; reviewed related user-story PRs for shared Godot API integration.
- Prototyped the D2 workflow scene, telemetry layout, connector interaction model, and user-story integration boundaries in PR #18. The prototype was superseded by the final grid-world rather than merged into the release.
- Coordinated communication with AMD and carried partner requirements and feedback into team planning.

## Isaac Tilahun - Environment and agent API

- Defined the US1 `Agent`, `Environment`, and `InteractionDefinition` contracts and the Godot behavior hooks for observation, action, reset, reward, and episode completion (#11).
- Revised the contract after team and partner review to use a single logical `step()`, leave validation to Python, and support standalone inference agents.
- Implemented a C++ reference grid-world with 19 tests for seeding, rewards, episode completion, and invalid input, including US4 lifecycle integration (#27).

## Jimmy Zhu - Spaces, points, QA, and D2 demo

- Defined the US2 space and point API, revised after review to use the shared `Status` type and match Python's Dict key order, and implemented Box, Discrete, MultiDiscrete, MultiBinary, and Dict spaces and points, including validation, flattening, and defaults (#7, #19, #30).
- Added the `ScholaBoxSpace`, `ScholaDiscreteSpace`, `ScholaMultiDiscreteSpace`, `ScholaMultiBinarySpace`, and `ScholaDictSpace` Inspector resources, strict Godot value conversion, configuration errors for invalid definitions, and the `space_to_dictionary` layout sent to Python, with `src/interop` added to the runtime build (#30).
- Worked with Vansh (US5) to review the environment and agent bindings, and majorly planning of the US2 API and implementation they rely on for Inspector space configuration and value conversion.
- Implemented protobuf conversion of spaces, points, interaction definitions, and agent states for US3's message conversion (#30).
- Added Catch2 tests for spaces, points, and protobuf round trips, and GdUnit4 integration tests for the space resources (#19, #30).
- Built the D2 grid-world demo project, including the playable environment, agent and environment stand-ins following the US1 and US5 contracts, tabular Q-learning trainer, runtime controls, reward graph, and saved-policy mode, with a summary of which parts are real and which are stand-ins (#19).
- Wired native US2 validation into every demo observation and action, showed each space's status in the editor dock and HUD, and verified that the saved Q-table policy reached the goal in 30 of 30 episodes (#19).

## Bohdan Zmeul - ONNX inference and packaging

- Defined the US7 policy, policy-state, stepper, and Godot inference APIs and aligned them with AMD's upstream recurrent-state design (#2, #14, #15).
- Pinned ONNX Runtime 1.30 with a checksum-verified setup script, linked it into the runtime add-on and CI, and listed it as an add-on dependency so it ships with the extension.
- Implemented the default `Policy` behavior, `EmptyPolicyState`, and `SimpleStepper` with one policy state per agent entry.
- Implemented `OnnxPolicy`: loading models from bytes, checking them against the observation and action spaces, inference for all space types, and recurrent state with a sliding window.
- Added the `ScholaOnnxPolicy` and `ScholaPolicyState` Godot bindings, and 27 inference test cases covering generated fixture models and real Schola-exported PPO models checked against Python results.
- Integrated the ONNX policy into the D2 demo, added Q-table-to-ONNX export and equivalence checks, and verified 30 of 30 trained-policy episodes reached the goal with Python closed (#23).
