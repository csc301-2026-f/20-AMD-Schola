# User stories

This directory is the canonical home for the project's approved MVP and stretch stories, and current implementation progress.

| Story | Title | Owner(s) | Status |
|---|---|---|---|
| [US1](US1.md) | Define a reinforcement-learning environment | Isaac and Sanjay | Complete on main |
| [US2](US2.md) | Declare observation and action spaces | Jimmy | Complete on main |
| [US3](US3.md) | Connect to existing Python training tools | Sanjay and Isaac | gRPC core merged; scene connector in progress |
| [US4](US4.md) | Execute the episode lifecycle | Shahyar | Complete on main |
| [US5](US5.md) | Configure Schola through Godot-native tools | Vansh | Native configuration merged |
| [US7](US7.md) | Run and ship an ONNX policy | Bohdan | Complete on main |
| [US8](US8.md) | Compose agents from reusable sensors and actuators | Guneev | Implemented on feature branch; PR open |
| [US9](US9.md) | Test an environment without Python | Unassigned | Approved; standalone workflow pending |
| [US10](US10.md) | Stack recent observations | Jimmy and Shahyar | Implemented and tested on feature branch; PR open |
| [US11](US11.md) | Observe the environment through a camera sensor | Unassigned | Approved; Godot implementation pending |
| [US12](US12.md) | Train multiple agents simultaneously | Unassigned | Multi-agent routing tested; Python training proof pending |
| [US13](US13.md) | Train and deploy through a production example | Bohdan | RaceTrack draft on feature branch; end-to-end proof pending |
| [US14](US14.md) | Read the state sequence length from the model | Jimmy | Implemented on feature branch; real-trainer fixture blocked upstream |
| [US15](US15.md) | Define observation and action spaces in code | Vansh | Callback and constructors on feature branch; runtime resolution pending |

Alex approved US8-US14 at the [Nov. 6 partner meeting](../../../deliverables/team/minutes/partner-meeting-07.md). US8, US12, and US13 are the highest-priority MVP stories; US9, US10, US11, and US14 are stretch goals. Statuses were reviewed on Nov. 17, 2026 against GitHub PRs, merge commits and feature branch history.

US6 is not part of the approved MVP story set.

See [Remaining work and future opportunities](remaining.md) for integration tasks and Unreal Schola capabilities that are not represented as active user stories.
