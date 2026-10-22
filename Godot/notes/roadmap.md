# US4 Roadmap: D2 to D4

US4 has 3 remaining course milestones:

| Milestone | Date |
|---|---|
| D2 | October 23, 2026 at 11:59 p.m. |
| D3 | November 6, 2026 |
| D4 presentation | November 24 or 26, 2026 |
| D4 submission | November 27, 2026 |

## D2: implement the lifecycle

- Add a deterministic fake environment.
- Implement `EnvironmentLifecycle`.
- Add Catch2 coverage for lifecycle transitions, failures, step limits, and repeated episodes.
- Integrate the lifecycle with Guneev's coordinator through its public API.
- Agree on the host contract with the US3 owner.
- Demonstrate at least 1 complete episode workflow.
- Record the ownership split and individual contributions in the D2 documents.

## D3: complete integration

- Implement `ScholaTrainingHost`.
- Add host discovery, conversion, delegation, lifetime, and shutdown tests.
- Implement the connector-to-lifecycle multi-episode acceptance test.
- Verify all 3 autoreset modes through the integrated system.
- Update developer and user documentation to match the implementation.

## D4: harden and hand off

- Fix defects found during full-system testing and add regression tests.
- Test scene replacement, environment removal, shutdown, and fault paths.
- Verify the separation of training-only and shipped runtime components.
- Rehearse the final workflow before the D4 presentation.
- Finalize setup, architecture, usage, and troubleshooting documentation.
- Produce a reproducible final build and release.

