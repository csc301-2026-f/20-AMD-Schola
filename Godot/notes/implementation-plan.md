# Shahyar's US4 Implementation Plan

The required lifecycle APIs are merged.

## 1. Confirm the baseline

- Build the existing Godot targets before changing behavior.
- Confirm `environment_lifecycle.cpp` compiles with the merged US1, US2, and US4 headers.
- Do not modify the merged public lifecycle API unless implementation reveals a documented contract defect.

## 2. Add a deterministic fake environment

Create or extend a core test double with:

- stable definitions and at least 2 agents;
- deterministic reset observations, step observations, and rewards;
- configurable termination and truncation;
- recorded actions and reset settings;
- injected failures for initialize, reset, and step.

Keep the fake independent of Godot so lifecycle tests run through Catch2.

## 3. Implement `EnvironmentLifecycle`

Implement in this order:

1. Constructor, ID access, and state inspection.
2. One-time initialization and definition storage.
3. Reset from `RESET_PENDING`, `ACTIVE`, and `COMPLETE`.
4. Logical stepping from `ACTIVE`.
5. Episode step counting and configured truncation.
6. Completion when every agent has finished.
7. Output preservation on failed calls.
8. Fault transitions after environment-operation failures.
9. Idempotent closure from every state.

## 4. Implement `ScholaTrainingHost`

After Guneev's coordinator contract is available:

1. Add the Godot-facing host under the training bindings module.
2. Discover valid `ScholaEnvironment` nodes and freeze their order for the session.
3. Keep the non-owned environment adapters alive and create one `EnvironmentLifecycle` per environment.
4. Transfer the lifecycle collection to `EnvironmentCoordinator`.
5. Bind the auto-reset, definition, reset, step, and close methods expected by US3's `HostTrainingBackend`.
6. Create and own the US3 `ScholaTrainingConnector` for the training session.
7. Reject operations after close and release the connector, backend, coordinator, and environment references safely.

Only the Godot main thread may access nodes, the scene tree, signals, or user callbacks.

## 5. Verify the handoffs

- `EnvironmentCoordinator` must be able to compose the lifecycle solely through its public API.
- Do not implement multiple-environment routing or autoreset modes; those belong to Guneev.
- The host delegates multi-environment reset, step, and autoreset behavior to Guneev's coordinator.
- US3 owns `HostTrainingBackend`, `ConnectorLoop`, `ScholaTrainingConnector`, and protocol transport; use those public APIs rather than duplicating them.
- Do not add a public two-phase stepping API or mandatory engine-side point validation.

## Completion checklist

- All lifecycle state transitions have Catch2 coverage.
- Failed calls preserve output values as documented.
- Environment failures transition the lifecycle to `FAULTED`.
- Reset removes all prior episode-local state.
- Step-limit truncation preserves agents already terminated or truncated.
- Returned definitions and states own their data.
- Core lifecycle files contain no Godot, gRPC, Protocol Buffer, or ONNX Runtime types.
- Host methods convert at the Godot boundary and delegate typed lifecycle work to the coordinator.
- Host startup and shutdown preserve main-thread access and safe object lifetimes.
- `git diff --check` and the applicable Godot build and tests pass.
