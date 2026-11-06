# US3: Connect to existing Python training tools

- **Owner:** Sanjay
- **Status:** In progress
- **Last updated:** Nov. 5, 2026

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
- PR #35 adds committed Windows/Linux x86_64 gRPC packages, checksum/provenance verification, Protocol Buffer generation, and training-message conversions. Normal setup installs the committed package without compiling or downloading gRPC; explicit `--from-source` rebuilds remain available. The versions match Unreal Schola and await AMD confirmation.
- Space/point and training-message conversion tests are included in the `transport_tests` target and invoked by CI. These test files do not establish a completed Python-to-Godot transport session.
- The concrete `GrpcConnector` still has only a header; `grpc_connector.cpp`, the Godot-facing transport implementation, and end-to-end tests with the existing Schola Python client remain unfinished.
- The D3 demo uses the localhost JSON/TCP stand-in and a tabular learner. Its runner calls the native US4 host, but does not exercise the production gRPC connector.
