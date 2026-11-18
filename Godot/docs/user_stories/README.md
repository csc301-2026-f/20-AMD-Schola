# User stories

This directory is the canonical home for the project's approved MVP and stretch stories, and current implementation progress.

| Story | Title | Owner(s) | Status |
|---|---|---|---|
| [US1](US1.md) | Define a reinforcement-learning environment | Isaac and Sanjay | Complete on main |
| [US2](US2.md) | Declare observation and action spaces | Jimmy | Complete on main |
| [US3](US3.md) | Connect to existing Python training tools | Sanjay and Isaac | gRPC core merged; scene connector in progress |
| [US4](US4.md) | Execute the episode lifecycle | Shahyar | Complete on main |
| [US5](US5.md) | Configure Schola through Godot-native tools | Vansh | Native configuration merged |
| [US7](US7.md) | Run and ship an ONNX policy | Bohdan | Inference and packaging merged; production training proof tracked in US13 |
| [US8](US8.md) | Compose agents from reusable sensors and actuators | Guneev | Implemented on feature branch; PR open |
| [US9](US9.md) | Test an environment without Python | Shahyar | Complete |
| [US10](US10.md) | Stack recent observations | Jimmy and Shahyar | Complete on main; live Python training not yet verified |
| [US11](US11.md) | Observe the environment through a camera sensor | Unassigned | Approved; Godot implementation pending |
| [US12](US12.md) | Train multiple agents simultaneously | Unassigned | Multi-agent routing tested; Python training proof pending |
| [US13](US13.md) | Train and deploy through a production example | Bohdan | RaceTrack PR open; export/inference checks added; real training proof pending |
| [US14](US14.md) | Read the state sequence length from the model | Unassigned | Upstream prerequisite merged; Godot implementation pending |
| [US15](US15.md) | Define observation and action spaces in code | Vansh | Adapter resolution on feature branch; startup integration and validation pending |

Alex approved US8-US14 at the [Nov. 6 partner meeting](../../../deliverables/team/minutes/partner-meeting-07.md). US8, US12, and US13 are the highest-priority MVP stories; US9, US10, US11, and US14 are stretch goals. All story records were reviewed on Nov. 18, 2026 against live GitHub PR states, remote branch commit IDs, merge commits, and branch history. This review does not constitute a new test run for other contributors' branches.

## Review evidence (Nov. 18)

- Remote `main` is `dac00c0`. US1, US2, US4, US5, and US7 retain their merged implementation statuses; US7 now explicitly separates inference/packaging from the outstanding production learning proof in US13. Additional US1 adapter tests merged in [#53](https://github.com/csc301-2026-f/20-AMD-Schola/pull/53); US10 merged in [#55](https://github.com/csc301-2026-f/20-AMD-Schola/pull/55) at `23b2338`.
- Open PRs are [#50](https://github.com/csc301-2026-f/20-AMD-Schola/pull/50) (US13, `26866ad`), [#51](https://github.com/csc301-2026-f/20-AMD-Schola/pull/51) (US8, `fc4ab9b`), and [#52](https://github.com/csc301-2026-f/20-AMD-Schola/pull/52) (US1/US4 dynamic populations, `fdccf51`). All three are marked ready for review, not draft.
- US3's scene connector is on `Isaac-Sanjay/us3/godot-training-connector` at `2663948`; US15 is on `Vansh/us15-code-defined-spaces` at `bc5694c`. Neither branch has a PR in the reviewed repository history.
- US9 provides a standalone debugging example using the production host and existing monitor. Its five example tests and 13 existing host tests passed in a runtime-only project, including rendered keyboard regression verification.
- No dedicated remote branches or PRs were found for US11, US12, or US14. Their owners remain unassigned. Related infrastructure is not evidence that these stories have been claimed.
- [Upstream #58](https://github.com/GPUOpen-LibrariesAndSDKs/Schola/pull/58) merged on Nov. 18 at `1b0e788`, satisfying US14's exporter prerequisite. The Godot implementation is still pending.

US6 is not part of the approved MVP story set.

See [Remaining work and future opportunities](remaining.md) for integration tasks and Unreal Schola capabilities that are not represented as active user stories.
