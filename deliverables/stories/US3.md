# US3: Connect to existing Python training tools

- **Owner:** Sanjay
- **Status:** In progress
- **Last updated:** Oct. 30, 2026

## Story

As an ML practitioner, I want a Godot environment to connect to Schola's existing Python training tools so that I can train policies without maintaining a separate Godot-specific Python workflow.

## Acceptance criteria

- The Godot integration completes the connection and environment-definition exchange with the existing Python client.
- The integration uses Schola's existing protocol and gRPC services unless AMD approves an alternative.
- The transport implements `StartGymConnector`, `RequestTrainingDefinition`, and `UpdateState` from the existing Gym connector protocol.
- Python can discover the available environment, agents, observation spaces, and action spaces.
- The transport is isolated behind a core interface so the engine-independent code does not depend directly on gRPC.
- Connection failures and incompatible protocol data produce actionable errors instead of hanging the game or training process.

## Progress

- The connector loop, training messages, and gRPC boundary have been defined.
- The blocking `tick` model was retained and `poll_tick` was removed from the design.
- Remaining work includes completing the concrete gRPC integration and its integration tests.
- No new progress was discussed at the Oct. 30 partner meeting because the owner was absent.
