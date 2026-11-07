# User stories

This directory is the canonical home for the project's approved MVP and stretch stories, and current implementation progress.

| Story | Title | Owner(s) | Status |
|---|---|---|---|
| [US1](US1.md) | Define a reinforcement-learning environment | Isaac and Sanjay | Complete |
| [US2](US2.md) | Declare observation and action spaces | Jimmy | Core and Godot resources complete; protobuf tests wired into transport CI |
| [US3](US3.md) | Connect to existing Python training tools | Sanjay and Isaac | In progress |
| [US4](US4.md) | Execute the episode lifecycle | Shahyar | Complete |
| [US5](US5.md) | Configure Schola through Godot-native tools | Vansh | Core bindings implemented |
| [US7](US7.md) | Run and ship an ONNX policy | Bohdan | Complete |
| [US8](US8.md) | Compose agents from reusable sensors and actuators | Unassigned | Approved - MVP; progress not yet reported |
| [US9](US9.md) | Test an environment without Python | Unassigned | Approved - Stretch; progress not yet reported |
| [US10](US10.md) | Stack recent observations | Unassigned | Approved - Stretch; progress not yet reported |
| [US11](US11.md) | Observe the environment through a camera sensor | Unassigned | Approved - Stretch; progress not yet reported |
| [US12](US12.md) | Train multiple agents simultaneously | Unassigned | Approved - MVP; progress not yet reported |
| [US13](US13.md) | Train and deploy through a production example | Unassigned | Approved - MVP; progress not yet reported |
| [US14](US14.md) | Read the state sequence length from the model | Unassigned | Approved - Stretch; progress not yet reported |

Alex approved US8-US14 at the [Nov. 6 partner meeting](../../../deliverables/team/minutes/partner-meeting-07.md). US8, US12, and US13 are the highest-priority MVP stories; US9, US10, US11, and US14 are stretch goals. Owners remain unassigned, and approval does not establish that implementation has started. US14 work waits for Alex's ONNX metadata-export PR to land.

US6 is not part of the approved MVP story set.

See [Remaining work and future opportunities](remaining.md) for integration tasks and Unreal Schola capabilities that are not represented as active user stories.
