# US4: Episode Lifecycle Ownership

This file is the source of truth for the US4 split. Supporting design, implementation, test, and roadmap details are linked at the end.

## Ownership

### Shahyar: single-environment lifecycle and training-session composition

Shahyar owns:

- `EnvironmentLifecycle`, including initialization, reset, step, completion, failure, and closure;
- episode step counting and step-limit truncation;
- preservation of terminal state and isolation between episodes;
- lifecycle unit tests against a deterministic fake `Environment`;
- the Godot-facing `ScholaTrainingHost`;
- discovery and retention of training environments for a session;
- construction of 1 lifecycle per environment and transfer of those lifecycles to the coordinator;
- host methods required by US3's `HostTrainingBackend`;
- training-session startup, shutdown, and Godot object lifetime management; and
- host integration tests.

### Guneev: multi-environment coordination and autoreset

Guneev owns:

- `EnvironmentCoordinator`;
- ownership and deterministic ordering of multiple lifecycle instances;
- routing reset and step requests across environments;
- disabled, same-step, and next-step autoreset behavior;
- batch result assembly;
- coordinator-wide failure handling; and
- coordinator, autoreset, ordering, routing, and cross-environment isolation tests.

### Shahyar's integration gate

Shahyar owns the end-to-end test that runs multiple episodes through the connector, host, coordinator, and lifecycle without deadlock or state leakage. Guneev reviews the coordinator and autoreset coverage within that test.

## Boundary rules

- `EnvironmentLifecycle` handles exactly 1 non-owned `Environment`.
- `EnvironmentCoordinator` composes lifecycle instances and owns all multi-environment and autoreset behavior.
- `ScholaTrainingHost` creates the session and delegates define, reset, step, autoreset, and close operations to the coordinator.
- The host must not reproduce coordinator routing or autoreset logic.
- The coordinator may use only the public `EnvironmentLifecycle` API.
- US3 owns `HostTrainingBackend`, `ConnectorLoop`, `ScholaTrainingConnector`, and transport behavior. US4 integrates with those public APIs without reproducing them.
- Godot nodes, the scene tree, signals, and user callbacks may be accessed only on the main thread.

## Required lifecycle behavior

- Initialize once and transition from `UNINITIALIZED` to `RESET_PENDING`.
- Reset from `RESET_PENDING`, `ACTIVE`, or `COMPLETE`, clear episode-local state, and return an owned initial observation.
- Step only from `ACTIVE` and return an owned snapshot of observations, rewards, termination, and truncation.
- Increment the episode step count once after each successful step.
- At a nonzero step limit, truncate agents that have not already terminated or truncated.
- Transition to `COMPLETE` only when every agent has terminated or truncated.
- Leave state and output parameters unchanged when validation fails before an environment call begins.
- Transition to `FAULTED` when an environment operation fails after it begins.
- Reject every operation except `close()` while faulted.
- Make `close()` idempotent and legal from every state.
- Forward normal actions and observations without exhaustive engine-side point validation; Python owns space validation.
- Accept Godot's consistent frame lag without adding a mandatory 2-phase public step API.

## Dependencies

- US1 supplies `Environment`, definitions, reset behavior, and logical stepping.
- US2 supplies owned `Point` and `Space` representations.
- US3 supplies the connector and `HostTrainingBackend` boundary.
- Shahyar can implement and test `EnvironmentLifecycle` before the coordinator is complete.
- Host integration starts after the coordinator and US3 host-call contract are available.

## Completion criteria

Shahyar's work is complete when:

- all lifecycle transitions and failure rules have Catch2 coverage;
- repeated episodes show no state leakage;
- returned definitions and states own their data;
- lifecycle files contain no Godot, gRPC, Protocol Buffer, or ONNX Runtime types;
- the host discovers environments deterministically and creates exactly 1 lifecycle for each environment;
- every host operation converts at the Godot boundary and delegates to the coordinator;
- startup and shutdown preserve main-thread access and safe object lifetimes;
- host integration tests pass; and
- Shahyar's end-to-end US4 acceptance test passes.

## Supporting documents

- [Design](design.md)
- [Implementation plan](implementation-plan.md)
- [Test plan](test-plan.md)
- [Open decisions](open-questions.md)
- [D2-D4 roadmap](roadmap.md)

