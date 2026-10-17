# US4 Open Decisions

Resolved behavior belongs in [US4.md](US4.md) and [design.md](design.md). This file contains only decisions that can still block implementation.

## Required before host implementation

- [ ] Agree with the US3 owner on the exact bound host method names.
- [ ] Define the Variant input and output shape for every host method.
- [ ] Define conversion errors and how HostTrainingBackend receives them.
- [ ] Decide how the host is created and how HostTrainingBackend receives or discovers it.
- [ ] Decide when the environment set is frozen.
- [ ] Define behavior when an environment is removed or the scene is replaced.
- [ ] Confirm whether the synchronous step path requires internal action buffering. Do not add buffering without evidence that it is required.
- [ ] Define the shutdown order for connector, backend, coordinator, lifecycle instances, and environment adapters.

## Required before US4 acceptance

- [ ] Agree on the test boundary: connector, host, coordinator, lifecycle, and deterministic fake or demonstration environment.
- [ ] Confirm the expected evidence for the D2 demo and individual-contribution record.

## Optional

- [ ] Decide whether the first implementation needs opt-in debug validation. Deferring it is acceptable; it must not change production behavior or the public lifecycle API.

