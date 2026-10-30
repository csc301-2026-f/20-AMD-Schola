# US1: Define a reinforcement-learning environment

- **Owner(s):** Isaac and Sanjay
- **Status:** In progress
- **Last updated:** Oct. 30, 2026

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

- The adapters API and Godot bind hooks are complete. Developers can override hooks such as `observe`, `act`, and `define`.
- The agent adapter is complete.
- The environment adapter header is complete; its implementation remains.
- After the environment adapter is implemented, the remaining work is end-to-end testing and cleanup.
