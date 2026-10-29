# US4 Completion Plan

## Goal

Complete the Godot-facing episode-lifecycle host that connects the existing `EnvironmentLifecycle` and `EnvironmentCoordinator` implementation to the interfaces owned by US1, US3, and US5.

US4 is complete when a fixed set of configured Godot environments can be discovered, initialized, reset, stepped through multiple episodes, and closed without state leakage or scene-tree access outside the main thread.

## Current state

Complete on `main`:

- [x] Engine-independent environment lifecycle.
- [x] Multiple-environment coordinator.
- [x] Disabled, same-step, and next-step autoreset behavior.
- [x] Lifecycle validation, failure handling, counters, and core unit coverage.

Present on this branch:

- [x] Initial `ScholaTrainingHost` scene-discovery and lifecycle-construction scaffold.
- [x] Runtime-extension registration for `ScholaTrainingHost`, alongside the US5 environment nodes it adapts.

## Ownership boundaries

US4 owns:

- `EnvironmentLifecycle` and `EnvironmentCoordinator` behavior.
- `ScholaTrainingHost` session state and main-thread orchestration.
- Stable environment ordering and lifecycle ownership for one training session.
- Delegation of define, reset, step, autoreset, and close operations to the coordinator.
- US4-specific host diagnostics and integration coverage.

US4 does not own:

- US1 environment or agent behavior and contracts.
- US2 space, point, or Variant conversion rules.
- US3 connectors, gRPC transport, polling, timeouts, or protocol messages.
- US5 scene-node configuration, Inspector properties, or environment validation rules.
- US7 inference and policy execution.

Changes to another story's public contract require that story owner's review and should be submitted separately from the US4 implementation.

## Confirmed partner constraints

Alex's October 23 review established these constraints for the remaining US4 work:

- Scene-tree discovery and user callbacks run on the Godot main thread.
- Environment-to-ID mappings remain fixed during a training run and may be rebuilt between runs.
- Adding or removing environments during a run is unsupported.
- A failure in any environment fails and closes the entire training session.
- US4 returns the failure and closes its lifecycle state; US3 owns any graceful close notification sent to Python.

## Implementation plan

### 1. Define the host boundary

- [x] Keep `EnvironmentCoordinator` and all lifecycle state owned by `ScholaTrainingHost`.
- [x] Keep `ScholaTrainingHost` in the runtime extension so it can use the US5 `ScholaEnvironment` C++ API without crossing a shared-library ABI boundary.
- [x] Define the smallest callable host surface required by US3's existing `TrainingBackend` contract:
  - [x] set autoreset mode;
  - [x] define the fixed environment set;
  - [x] reset;
  - [x] step;
  - [x] close.
- [ ] Keep scene-tree access and user callbacks on the Godot main thread.
- [x] Do not add transport or connector behavior to the host.
- [x] Bind the host operations through Godot so US3's training extension can call them through `godot::Object` and Variant-compatible values without linking to runtime C++ types.

Deliverable: a runtime-owned lifecycle host with a Godot ABI boundary for the training extension.

### 2. Complete session discovery

- [x] Discover top-level trainable environment nodes in deterministic scene-tree order.
- [x] Reuse US5 configuration diagnostics rather than duplicating its validation rules.
- [ ] Reject an empty environment set and any invalid environment configuration with an actionable status.
- [x] Assign contiguous `EnvironmentId` values based on discovery order.
- [x] Create one `EnvironmentLifecycle` per discovered US1 environment adapter.
- [x] Store Godot `ObjectID` values only for non-owning identity checks; Godot retains node ownership.
- [x] Publish the new environment list only after every candidate validates successfully.
- [x] Reject repeated initialization for the same active session.

Deliverable: atomic initialization of a fixed, ordered coordinator session.

### 3. Implement host operations

- [x] Route autoreset configuration to `EnvironmentCoordinator::set_autoreset_mode`.
- [x] Route definition, reset, step, and close operations to the coordinator.
- [x] Cache the successful training definition for the fixed session and clear it on close.
- [x] Preserve output arguments when an operation fails.
- [x] Reject operations before initialization and after close with `FAILED_PRECONDITION`.
- [ ] Treat a missing, freed, or failed environment node as a session failure; close the coordinator and return the original failure without attempting mid-session remapping.
- [x] Make close idempotent and safe after partial initialization.

Deliverable: complete US4 behavior behind the existing `TrainingBackend` operation set.

### 4. Add the Godot-facing adapter

- [x] Bind only the methods needed by US3's `HostTrainingBackend`.
- [x] Translate US4 statuses into Godot-facing results without creating a second error channel.
- [x] Use the shared interop layer for existing value conversions; do not add US4-specific replacements for US2 or US3 conversion logic.
- [x] Decode step actions against each cached agent action space without changing the session mapping.
- [x] Require `HostTrainingBackend` to call a generic `godot::Object`; do not expose `ScholaTrainingHost`, coordinator, environment, or other runtime C++ pointers across the extension boundary.
- [x] Keep connector creation, network configuration, and protocol scheduling outside `ScholaTrainingHost`.

Deliverable: a host surface that US3 can call without linking to US4 implementation details.

### 5. Handle scene lifecycle and shutdown

- [ ] Close the coordinator when the host leaves the scene tree.
- [ ] Prevent new work once shutdown begins.
- [ ] Ensure no worker thread reads or mutates Godot objects through the host.
- [ ] Return the first actionable shutdown failure while still attempting required cleanup.
- [ ] Expose enough close status for US3 to attempt its protocol notification without implementing that notification in US4.

Deliverable: deterministic cleanup after normal close, partial startup, or scene removal.

### 6. Add US4-focused verification

- [ ] Cover discovery order and stable environment IDs.
- [ ] Cover empty, invalid, nested, and freed environment-node cases using the public US5 behavior.
- [ ] Cover duplicate initialization and operations before initialization.
- [ ] Cover define, reset, step, all autoreset modes, and idempotent close through the host boundary.
- [ ] Cover multiple episodes and multiple environments without state or counter leakage.
- [ ] Cover partial initialization failure without publishing a half-built session.

Do not duplicate US1 environment tests, US3 connector tests, US5 Inspector tests, or the existing engine-independent lifecycle suite.

Deliverable: integration evidence for the remaining D1 US4 acceptance criterion.

## Completion criteria

- [x] `ScholaTrainingHost` lives with the runtime environment bindings, while US3 reaches it only through Godot-bound methods and Variant-compatible values.
- [x] One fixed environment mapping is used for the duration of a session.
- [x] Every lifecycle operation is available through the host boundary and delegates to the existing coordinator.
- [ ] All Godot object access occurs on the main thread.
- [ ] Startup and shutdown are safe after partial failure.
- [ ] US3 can use the host through its existing backend abstraction without US4 implementing transport behavior.
- [ ] Focused host integration coverage demonstrates multiple episodes without deadlock or state leakage.
