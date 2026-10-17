# Shahyar's US4 Test Plan

Use deterministic Catch2 tests against a fake US1 `Environment` for the core lifecycle. Add Godot integration tests for Shahyar's `ScholaTrainingHost`. Coordinator internals and autoreset semantics remain Guneev's scope.

Ownership and completion criteria are defined in [US4.md](US4.md). This file lists Shahyar's test cases and the shared acceptance boundary.

## Construction and initialization

- The lifecycle reports its configured environment ID and begins `UNINITIALIZED`.
- Initialization succeeds once and transitions to `RESET_PENDING`.
- The returned definition remains stable and owns its data.
- Repeated initialization fails without changing state.
- An initialization failure transitions to `FAULTED`.

## Reset

- Reset succeeds from `RESET_PENDING`, `ACTIVE`, and `COMPLETE` and ends `ACTIVE`.
- Seed and options reach the environment unchanged.
- Reset clears the episode step count and cached episode state.
- Reset returns owned initial state.
- Reset from an invalid state leaves its output unchanged.
- An environment reset failure leaves its output unchanged and transitions to `FAULTED`.

## Step

- Step succeeds only from `ACTIVE`.
- Actions reach the environment without exhaustive point validation.
- Observations, rewards, termination, and truncation are returned as owned values.
- Finished-agent terminal state is preserved.
- The lifecycle becomes `COMPLETE` only when every agent has terminated or truncated.
- Results remain unchanged after later resets or steps.
- A step precondition failure leaves state and output unchanged.
- An environment step failure leaves output unchanged and transitions to `FAULTED`.

## Episode step limit

- A zero limit never adds step-based truncation.
- Each successful step increments the episode count exactly once.
- Reaching a nonzero limit truncates unfinished agents.
- Agents already terminated or truncated are not overwritten.
- Reset returns the count to zero.

## Fault and close behavior

- A faulted lifecycle rejects initialize, reset, and step.
- `close()` succeeds from every state, including `FAULTED`.
- Repeated close succeeds without additional environment work.
- Operations after close fail without changing outputs.

## Episode isolation

- Several reset-and-step cycles complete without observations, rewards, completion flags, or step counts leaking between episodes.

## ScholaTrainingHost integration

- The host discovers only valid training environments and freezes deterministic session order.
- Each discovered environment receives exactly one lifecycle with the configured step limit.
- Bound define, reset, step, auto-reset configuration, and close calls delegate to the coordinator.
- Variant conversion failures become explicit Godot-facing errors without partially changing outputs.
- Host calls that access Godot objects execute on the main thread.
- Closing the host rejects new operations and releases session objects in a safe order.
- Removing an environment or replacing the scene closes or rejects the session without dangling references.
- US3's `HostTrainingBackend` can invoke every required bound host method.

## Handoff boundaries

Guneev's tests cover coordinator ownership, multiple-environment ordering, batch routing, failure propagation, and all autoreset modes. Shahyar's host integration tests verify delegation and lifecycle ownership without duplicating those coordinator behavior tests.

## Shared US4 acceptance test

Shahyar owns the end-to-end test that runs multiple episodes through the connector, host, coordinator, and lifecycle without deadlock or state leakage. Guneev reviews the coordinator and autoreset coverage within that test.
