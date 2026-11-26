# User stories

This directory is the canonical home for the project's approved MVP and stretch stories, and current implementation progress.

| Story | Title | Owner(s) | Status |
|---|---|---|---|
| [US1](US1.md) | Define a reinforcement-learning environment | Isaac and Sanjay | Complete on main |
| [US2](US2.md) | Declare observation and action spaces | Jimmy | Complete on main |
| [US3](US3.md) | Connect to existing Python training tools | Sanjay and Isaac | Complete on main |
| [US4](US4.md) | Execute the episode lifecycle | Shahyar | Complete on main |
| [US5](US5.md) | Configure Schola through Godot-native tools | Vansh | Complete on main |
| [US7](US7.md) | Run and ship an ONNX policy | Bohdan | Complete on main |
| [US8](US8.md) | Compose agents from reusable sensors and actuators | Guneev | Complete on main |
| [US9](US9.md) | Test an environment without Python | Shahyar | Complete on main |
| [US10](US10.md) | Stack recent observations | Jimmy and Shahyar | Merged; live trainer run with stacking unverified |
| [US11](US11.md) | Observe the environment through a camera sensor | Bohdan and Vansh | Merged; fully trained camera policy and wider renderer/platform checks pending |
| [US12](US12.md) | Train multiple agents simultaneously | Sanjay | Merged; recorded `schola rllib train` run pending |
| [US13](US13.md) | Train and deploy through a production example | Bohdan | Complete on main |
| [US14](US14.md) | Read the state sequence length from the model | Jimmy | Merged; real-trainer sequence fixture blocked upstream |
| [US15](US15.md) | Define observation and action spaces in code | Vansh | Complete on main; split space hooks in the merge queue (PR #93) |

Alex approved US8-US14 at the [Nov. 6 partner meeting](../../../deliverables/team/minutes/partner-meeting-07.md). US8, US12, and US13 are the highest-priority MVP stories; US9, US10, US11, and US14 are stretch goals. Statuses were reviewed on Nov. 25, 2026 against main at `f7e6fc7`, GitHub PRs, and the active Godot implementation. Open PRs describe proposed work and are not evidence of functionality on main.

US6 is not part of the approved MVP story set.

## Open pull requests

As of Nov. 25, 2026, these PRs affect story behavior or documentation but are not on main:

| PR | State | Story | Change |
|---|---|---|---|
| [#93](https://github.com/csc301-2026-f/20-AMD-Schola/pull/93) | In the merge queue | [US15](US15.md) | Breaking: replaces `_define_spaces()` and `ScholaSpaceDefinition` with separate `_define_observation_space()` and `_define_action_space()` hooks. It updates US15 itself. |
| [#98](https://github.com/csc301-2026-f/20-AMD-Schola/pull/98) | Open | [US1](US1.md) | Frees the ID of an agent that leaves during reset, so a later node can reuse it. |
| [#99](https://github.com/csc301-2026-f/20-AMD-Schola/pull/99) | Open | [US4](US4.md), [US7](US7.md) | Adds Godot-facing error rules to the development contract and names the failing method in every `ScholaTrainingHost` error. |
| [#100](https://github.com/csc301-2026-f/20-AMD-Schola/pull/100) | Open | [US1](US1.md) | Frees the ID of a birth that leaves during its first step instead of reporting it as terminated. |

See [Remaining work and future opportunities](remaining.md) for integration tasks and Unreal Schola capabilities that are not represented as active user stories.
