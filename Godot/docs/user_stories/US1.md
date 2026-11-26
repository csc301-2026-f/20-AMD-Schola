# US1: Define a reinforcement-learning environment

- **Owner(s):** Isaac and Sanjay
- **Status:** Complete on main
- **Last updated:** November 26, 2026

## Story

As a Godot developer, I want to define a reinforcement-learning environment through a small Godot-styled interface so that I can make an environment trainable without writing networking code.

## Acceptance criteria

- A developer can implement or configure the environment's initialization, reset, observation, reward, and terminal-state behavior.
- The interface looks native to Godot without carrying unnecessary Unreal-specific design decisions.
- The environment can contain at least one agent.
- Environment code does not directly manage sockets, RPC calls, or serialized protocol messages.
- The environment accepts a reproducible random seed and optional reset configuration.
- Invalid or incomplete environment configuration produces a clear error.

## Progress

- The production environment adapter merged in [PR #34](https://github.com/csc301-2026-f/20-AMD-Schola/pull/34) ([`3fd714d`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/3fd714d)). Additional adapter integration tests merged in [PR #53](https://github.com/csc301-2026-f/20-AMD-Schola/pull/53). Dynamic population support merged in [PR #52](https://github.com/csc301-2026-f/20-AMD-Schola/pull/52).
- The native agent and environment adapters are implemented and merged in #34.
- GDScript hooks expose actions, observations, reset behavior, rewards, termination, truncation, and info without requiring environment code to manage transport.
- Reset seeds and options reach environment scripts through the native adapter.
- The passing Godot host integration suite exercises the adapters across multiple environments, repeated episodes, all three autoreset modes, and configuration failures.
- `tests/integration/environment_adapter_test.gd` drives the environment adapter directly through the test-only driver. It covers initialization, seeded and unseeded resets, action checks before any agent moves, staggered episode endings, freed agents, and `get_agents()` order.

## Current integration evidence

Dynamic population handling preserves identities through pause/resume and validates possible-agent declarations. PRs #73, #76, #87, #97, #98, and #100 cover paused births and agents removed before their first published observation. An unpublished departure releases its ID; a published terminal agent keeps a retired ID until reset.

See the [verification record](../verification.md) for the checked main revision, passing CI jobs, and local verification.
