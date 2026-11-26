# US1: Define a reinforcement-learning environment

- **Owner(s):** Isaac and Sanjay
- **Status:** Complete on main
- **Last updated:** Nov. 25, 2026

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
- Later fixes on main: [PR #76](https://github.com/csc301-2026-f/20-AMD-Schola/pull/76) reports empty slots returned by `_get_possible_agents()`, [PR #73](https://github.com/csc301-2026-f/20-AMD-Schola/pull/73) preserves dynamic training identities and pause transitions, and [PR #97](https://github.com/csc301-2026-f/20-AMD-Schola/pull/97) lets a new node reuse the ID of a paused birth that left before Python saw it. Open PRs #98 and #100 fix the same ID reuse for an agent that leaves during reset and for a birth that leaves during its first step.
