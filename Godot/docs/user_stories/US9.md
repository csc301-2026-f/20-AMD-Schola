# US9: Test an environment without Python

- **Owner:** Shahyar
- **Status:** Implemented on feature branch; focused integration tests pass
- **Priority:** Stretch goal
- **Last updated:** Nov. 18, 2026

## Story

As a Godot developer, I want to reset and step a Schola environment without starting Python so that I can debug its reinforcement-learning behavior before running a training session.

## Rationale

Unreal Schola provides a manual connector for testing and debugging without an external trainer. Godot should expose the same capability through a small Godot-native API that exercises the production environment and lifecycle implementation.

## Acceptance criteria

- A developer can initialize and reset an environment with an optional seed and reset options.
- A developer can submit actions for the environment's agents and retrieve observations, rewards, termination, truncation, and info results.
- Manual operations use the production US1 and US4 contracts rather than a separate simulated lifecycle.
- The interface is callable from GDScript and automated Godot tests.
- Invalid actions and environment failures produce the same structured errors as a real training session.
- The workflow requires no Python process, gRPC connection, or training dependency.
- Tests demonstrate at least one complete episode, including reset and terminal-state handling.

## Progress

Implementation is on `Shahyar/us9-headless-python`; a PR has not been opened.
The five focused tests and 13 existing host tests passed together in rendered mode; the five
focused tests also passed headlessly.

The [manual environment example](../../examples/manual_environment/README.md)
uses the production `ScholaTrainingHost` API to initialize, define, reset, and
step an environment directly from GDScript. It shows observations, rewards,
termination, truncation, info, and structured errors, with explicit reset and
optional seeds and reset options. No new connector or lifecycle is introduced.
The existing `ScholaMonitor` displays real episode steps, returns, reward
history, and completion, alongside manual controls and raw structured results.

Five focused integration tests load the example scene and cover a complete
episode and reset, terminal-state preservation, truncation, seeded resets,
invalid actions without state advancement, and arrow-key movement while GUI
controls have focus (preserving seed-field editing). They pass in a separate project
containing only the runtime add-on, without the training extension or Python.
The runtime extension retains its existing ONNX Runtime dependency.

## Scope limits

- The story provides a callable API or small scene node, not a custom editor dock.
- It does not launch or manage Python processes from Godot.
