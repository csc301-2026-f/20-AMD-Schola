# US3: Connect to existing Python training tools

- **Owner:** Sanjay
- **Status:** In progress
- **Last updated:** Nov. 4, 2026

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
- `poll_tick` and `Connector::poll_update` were removed from the code, as AMD recommended at partner meeting 5.
- gRPC 1.80.0 and Protocol Buffers 31.1, the versions Unreal Schola uses, are built from source by `tools/setup_grpc.py` and linked into the training extension only. Generated bindings and a `transport_tests` target are part of the shared build. The build has been tested on macOS arm64; Linux runs in CI, and the Windows configuration has not been tested yet. The versions await AMD confirmation.
- Remaining work includes the concrete `GrpcConnector`, the training-message conversions, and their integration tests.
- No new progress was discussed at the Oct. 30 partner meeting because the owner was absent.
