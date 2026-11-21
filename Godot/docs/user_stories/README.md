# User stories

This directory is the canonical home for the project's approved MVP and stretch stories, and current implementation progress.

| Story | Title | Owner(s) | Status |
|---|---|---|---|
| [US1](US1.md) | Define a reinforcement-learning environment | Isaac and Sanjay | Complete on main; dynamic-population extension open in PR #52 |
| [US2](US2.md) | Declare observation and action spaces | Jimmy | Complete on main |
| [US3](US3.md) | Connect to existing Python training tools | Sanjay and Isaac | Transport and scene connector merged; trainer validation and reconnect follow-up open |
| [US4](US4.md) | Execute the episode lifecycle | Shahyar | Complete on main; dynamic populations and pause/resume open in PR #52 |
| [US5](US5.md) | Configure Schola through Godot-native tools | Vansh | Complete on main |
| [US7](US7.md) | Run and ship an ONNX policy | Bohdan | Complete on main |
| [US8](US8.md) | Compose agents from reusable sensors and actuators | Guneev | Complete on main (PR #51) |
| [US9](US9.md) | Test an environment without Python | Shahyar | Complete on main (PR #57) |
| [US10](US10.md) | Stack recent observations | Jimmy and Shahyar | Merged in PR #55; live Python training with stacking unverified |
| [US11](US11.md) | Observe the environment through a camera sensor | Bohdan and Vansh | Camera infrastructure merged; example and remaining validation in draft PR #60 |
| [US12](US12.md) | Train multiple agents simultaneously | Sanjay | Draft PR #61; Godot tests and Python random-action check reported; RLlib training pending |
| [US13](US13.md) | Train and deploy through a production example | Bohdan | Draft PR #50; trained policy and evaluation reported; retraining and clean-checkout proof pending |
| [US14](US14.md) | Read the state sequence length from the model | Jimmy | Merged in PR #62; real-trainer sequence fixture blocked upstream |
| [US15](US15.md) | Define observation and action spaces in code | Vansh | Implemented and locally tested in PR #58; review and merge conflicts pending |

Alex approved US8-US14 at the [Nov. 6 partner meeting](../../../deliverables/team/minutes/partner-meeting-07.md). US8, US12, and US13 are the highest-priority MVP stories; US9, US10, US11, and US14 are stretch goals. Statuses were checked on Nov. 21, 2026 against main at `083805b` and current merged/open PR heads. Feature-branch tests and scores are attributed to their PR records; they were not rerun for this documentation update.

US6 is not part of the approved MVP story set; the numbering contains 14 active stories. Ten have their primary implementation on main (US1–US5, US7–US10 and US14), with the validation gaps noted above. US11 has camera infrastructure on main but remains incomplete; US11–US13 and US15 have open feature PRs. “Merged” describes implementation availability, not automatic completion of every acceptance criterion.

Open PRs: [#50 — US13](https://github.com/csc301-2026-f/20-AMD-Schola/pull/50) (draft), [#52 — US1/US4 extensions](https://github.com/csc301-2026-f/20-AMD-Schola/pull/52), [#58 — US15](https://github.com/csc301-2026-f/20-AMD-Schola/pull/58), [#60 — US11](https://github.com/csc301-2026-f/20-AMD-Schola/pull/60) (draft), and [#61 — US12](https://github.com/csc301-2026-f/20-AMD-Schola/pull/61) (draft). PRs #52 and #58 currently have merge conflicts. The linked story pages separate merged work, branch evidence and remaining acceptance checks.

See [Remaining work and future opportunities](remaining.md) for integration tasks and Unreal Schola capabilities that are not represented as active user stories.
