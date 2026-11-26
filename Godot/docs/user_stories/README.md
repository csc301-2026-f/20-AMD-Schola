# User stories

These are the approved MVP and stretch stories for the Godot port. The current implementation is the C++ GDExtension under `Godot/`; the Unreal implementation and shared Python trainers are the foundation it extends.

| Story | User outcome | Owner(s) | Delivery |
| --- | --- | --- | --- |
| [US1](US1.md) | Define an environment and its agents | Isaac and Sanjay | Complete on main |
| [US2](US2.md) | Declare and validate observation/action spaces | Jimmy | Complete on main |
| [US3](US3.md) | Train through existing Schola Python tools | Sanjay and Isaac | Complete on main; SB3 and RLlib trainer evidence |
| [US4](US4.md) | Coordinate steps, results, resets, and episodes | Shahyar | Complete on main |
| [US5](US5.md) | Configure Schola with native nodes and Inspector resources | Vansh | Complete on main |
| [US7](US7.md) | Run and ship ONNX policies without Python | Bohdan | Complete on main |
| [US8](US8.md) | Compose reusable sensors and actuators | Guneev | Complete on main |
| [US9](US9.md) | Debug an environment without Python | Shahyar | Complete on main |
| [US10](US10.md) | Stack observation history for training and inference | Jimmy and Shahyar | Complete on main; live stacked-observation training passed |
| [US11](US11.md) | Use camera observations in training and inference | Bohdan and Vansh | Delivered on main; latest-completed-frame capture |
| [US12](US12.md) | Train simultaneous agents | Sanjay | Complete on main; Windows RLlib training recorded |
| [US13](US13.md) | Train, export, and deploy a production example | Bohdan | Complete on main; RaceTrack |
| [US14](US14.md) | Read recurrent state sequence length from ONNX metadata | Jimmy | Implemented on main; trainer fixture limitation documented |
| [US15](US15.md) | Define spaces through independent code hooks | Vansh | Complete on main |

Reviewed on November 26, 2026 against main at [`090ef506`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/090ef506f4a16c0e92c328743dfb5264f997903b), merged PRs, their review discussions, and the active registrations, examples, and tests. See the [verification record](../verification.md) for reproducible commands and results. RaceTrack, the camera workflow, independent space hooks, and the reviewed lifecycle/error-handling fixes are included in this implementation.

Alex approved US8-US14 at the [November 6 partner meeting](../../../deliverables/team/minutes/partner-meeting-07.md). US8, US12, and US13 are the highest-priority MVP stories; US9, US10, US11, and US14 are stretch goals. US6 is outside the approved MVP set.

The individual records retain acceptance criteria, delivered behavior, and material limits. [Future opportunities](remaining.md) distinguishes product extensions from maintenance. Submitted deliverables and demos preserve their original snapshots.
