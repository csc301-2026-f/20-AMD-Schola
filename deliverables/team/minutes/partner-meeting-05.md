# AMD Schola Partner Meeting 5

## Meeting details

- **Date:** Oct 23, 2026
- **Time:** 11:00 a.m.–12:30 p.m.
- **Location:** Microsoft Teams
- **Minutes prepared by:** Sanjay Ram / Shahyar Anfaz
- **Minutes source:** Shared Granola notes

## Attendees

### AMD

- Alexander Cann -- MTS @ AMD

### CSC301 team

- Guneev Pannu
- Sanjay Ram
- Bohdan Zmeul
- Vansh Sehrawat
- Shahyar Anfaz
- Isaac Tilahun
- Jimmy Zhu

## Progress review and technical discussion

### US1: Engine-independent reinforcement-learning API

- The core agent, environment, and supporting structs were defined, with Godot-adapter stubs in place.
- The agent interface provides `observe`, `define`, and `act`, following the shape of Unreal's `IAgent`.
- The environment interface covers initialization, reset, stepping, applying actions, returning observations and rewards, and retrieving agents.
- `get_agents` was added to support US7's multi-agent inference work.
- `InteractionDefinition`, `ResetSettings`, `AgentState`, and `AgentID` were adapted from their Unreal equivalents.
- The next step is building the Godot adapter with Sanjay, using US2 variant conversion and US5 spaces.

### US2: Spaces and points

- Most implementation work was complete, with a few edge cases and tests remaining.
- Spaces and points use a C++ union or variant, the closest equivalent to Unreal's `TInstancedStruct`.
- The partner suggested considering templates for compile-time type safety. A templated `point_t` and `space_t` design could prevent implicit casts and replace some runtime checks.
- The current runtime-checked approach remains acceptable if templates would add excessive complexity.

### US3: gRPC connector

- The connector loop handles startup handshake, step, reset, and close requests and routes them to the training backend.
- The connector handles Python-side requests, while `HostTrainingBackend` handles the Godot-facing side owned by US4.
- The design contained blocking `tick` and non-blocking `poll_tick` methods.
- The partner recommended removing `poll_tick`, because delaying actions and rewards harms reinforcement learning. Game state can advance before calling the blocking operation when polling-like behavior is needed.
- Remaining work included the concrete gRPC connector, training messages, SCons integration for gRPC C++, and integration tests.

### US4: Episode lifecycle

- The episode lifecycle and coordinator were complete, including all three automatic-reset modes and 30 passing tests.
- The implementation uses explicit active, completed, faulted, and closed states; returns descriptive `Status` values; and leaves output parameters unchanged after failed operations.
- `ScholaTrainingHost` must access the Godot scene tree on the main thread. Background threads may handle networking, conversion, and validation.
- Environment-to-ID mappings remain fixed during a training run but may change between runs.
- Adding or removing environments during a run is unsupported.
- If an environment fails during the loop, the session should close and return a failure.
- Shutdown should attempt to notify Python gracefully, while acknowledging that hard crashes cannot guarantee notification.
- Remaining work included multi-environment coordination and integration testing.

### US5: Godot scene nodes

- `ScholaEnvironment` and `ScholaAgent` were registered and exposed in the Godot Inspector.
- Environments expose `max_episode_steps`; agents expose `agent_id` and `agent_type`.
- Basic integration tests verify class registration and persistence of Inspector values.
- Agent IDs must be unique within an environment. Reusing an ID across different environments is intentional for replicated agents.
- Nested environments are unsupported.
- The partner noted ambiguity caused by separate reset, reward, termination, truncation, and info callbacks and suggested considering one step callback that returns all results together.
- Built-in maximum-step truncation may conflict with custom truncation logic. An optional Gymnasium-style wrapper may be clearer than a built-in property.

### US7: ONNX policy inference

- The core C++ layer contains the policy interface, `OnnxPolicy`, and per-agent `PolicyState` memory.
- The Godot layer contains a policy resource that loads ONNX files through Godot and an inference stepper that runs each physics frame.
- New recurrent memory is written separately and committed only after successful inference.
- The partner recommended reconsidering `get_last_error` when `Status` already carries error details and documenting recovery semantics for nonfatal errors.
- Initializers should consistently accept either an agent or an `InteractionDefinition`.
- Duplicate agents in a stepper are intentional to support shared observations such as fog of war.
- The team will check whether `max_state_sequence_length` should come from ONNX metadata instead of manual configuration.
- Full validation during inference is intentionally omitted for performance. An optional `ValidatedPolicy` wrapper could provide a pre-inference sanity check.

## Decisions

- Remove `poll_tick` from the connector loop and retain the blocking tick model.
- Keep environment-to-ID mappings stable during each training run.
- Do not support adding or removing environments mid-run.
- Close the training session if any environment fails during the loop.
- Keep expensive inference validation optional.

## Action items

| Owner            | Action                                                                                           | Status at meeting end |
|------------------|--------------------------------------------------------------------------------------------------|-----------------------|
| Isaac and Sanjay | Build the US1 Godot adapter using US2 conversion and US5 space types.                            | Open                  |
| Sanjay           | Remove `poll_tick` and implement the gRPC connector and training messages.                       | Open                  |
| Bohdan           | Confirm Unreal's `max_state_sequence_length` behavior.                                           | Open                  |
| Bohdan           | Revisit US7 error handling, initializer consistency, and the optional `ValidatedPolicy` wrapper. | Open                  |
| Team             | Continue the regular Friday partner meeting during reading week; Sanjay reported a conflict.     | Open                  |

## Logistics

- The following Friday meeting during reading week was confirmed for everyone except Sanjay, who had a conflict.
- The AMD advisor expected to attend a conference in Montreal during the week of Nov 8–14; the Friday meeting was still expected to proceed.
