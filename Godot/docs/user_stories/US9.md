# US9: Test an environment without Python

- **Owner:** Unassigned
- **Status:** Proposed
- **Last updated:** Oct. 30, 2026

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

## Scope limits

- The story provides a callable API or small scene node, not a custom editor dock.
- It does not launch or manage Python processes from Godot.
