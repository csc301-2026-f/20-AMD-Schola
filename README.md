# Schola for Godot - Team 20, The Hard Workers

Schola for Godot is a CSC301 project developed by our 7-person student team in partnership with AMD. The project is currently in its planning and prototyping stage.

## Partner introduction

Our partner is AMD, the organization that maintains the open-source Schola reinforcement-learning toolkit.

- **Primary contact:** Alexander Cann, Member of Technical Staff, [alexander.cann@amd.com](mailto:alexander.cann@amd.com)
- **Secondary contact:** TianYue "Michael" Liu, Senior Software Engineer, [tianyliu@amd.com](mailto:tianyliu@amd.com)

## Project description

We are building a Godot 4.7 port of AMD Schola. It will let Godot developers define reinforcement-learning environments and agents, train them with Schola's Python tools, export trained policies to ONNX, and run those policies inside Godot without Python. The port removes the need for developers to create their own engine-to-Python communication, episode coordination, and inference infrastructure.

## Key features

- **Godot-native environment definition:** Developers will configure environments and agents through Godot nodes and the Inspector.
- **Observation and action spaces:** The port will support Box, Discrete, MultiDiscrete, and MultiBinary spaces and validate values against their declared spaces.
- **Python training integration:** Godot environments will communicate with Schola's existing Python ecosystem through its gRPC protocol.
- **Complete episode lifecycle:** The integration will coordinate actions, observations, rewards, terminal states, truncation, and resets across complete episodes.
- **Local ONNX inference:** Exported policies will run inside Godot without a live Python process or training connection.
- **Separable packaging:** Training-only dependencies will be removable from exported games that only need inference.

The full MVP and its acceptance criteria are in the [D1 planning document](deliverables/D1/planning.md). The [architecture diagram](deliverables/D1/d1-architecture-diagram.png) shows the planned components and workflow.

## Instructions

The D1 interactive prototype is preserved in [`Godot/archive/d1_demo`](Godot/archive/d1_demo) as a historical reference, and a [video walkthrough is available on YouTube](https://youtu.be/zg4K3fiQjJw). It demonstrates Godot-native environment and agent nodes, configurable rewards and episode limits, reward feedback, and episode resets. It does not include a training backend or persistence.

The archived project requires Godot 4.7.2 with .NET support and the .NET 8 SDK. Its C# implementation is not the production add-on; the production add-on uses the native C++ GDExtension architecture. Environment and reward APIs are still being developed, so the demo has not been ported.

## Development requirements

The engine-side implementation targets Godot 4.7 and uses native C++ GDExtensions. The shared build, dependency, testing, packaging, and module foundation is defined; user-story APIs are implemented separately by their owners. The training integration will use gRPC and Protocol Buffers, while shipped-policy inference will use ONNX Runtime. The Python side will reuse Schola's Gymnasium, Stable-Baselines3, and RLlib integrations where practical.

See the [Godot development guide](Godot/README.md) for supported tools, dependency pins, build and test commands, module boundaries, and contribution workflow.

## Deployment and GitHub workflow

This project is a developer library rather than a hosted service. The Godot integration will be distributed as an add-on, with training-only code packaged separately from the core and inference components.

The 7 team members track work on the [Trello board](https://trello.com/b/Ry0Qkx2R). Each change is developed on a branch and submitted to `main` through a pull request. At least 1 other team member must review and approve the pull request before it is merged. The related Trello card remains in progress until the pull request is merged. This workflow keeps work attributable, reduces conflicts, and prevents unreviewed changes from entering `main`.

Commit messages follow Conventional Commits, using prefixes such as `feat:`, `fix:`, `docs:`, and `test:`. Changes that affect shared architecture or protocol behavior are discussed with the team and AMD before implementation.

## Coding standards and guidelines

C++ code follows Godot's C++ style and is formatted with `clang-format`. Python code follows PEP 8 and is formatted with Black. New behavior must include relevant tests, and generated Protocol Buffer files must not be edited by hand.

## License

The project uses the [MIT License](LICENSE.txt), matching AMD Schola. This permits use, modification, and redistribution while requiring preservation of the license and copyright notice.

## Project resources

- [D1 planning document](deliverables/D1/planning.md)
- [D1 architecture diagram](deliverables/D1/d1-architecture-diagram.png)
- [Archived D1 Godot prototype](Godot/archive/d1_demo)
- [Prototype video walkthrough](https://youtu.be/zg4K3fiQjJw)
- [Team and stakeholder records](deliverables/team/)
- [Meeting minutes](deliverables/team/minutes/)
- [Trello project board](https://trello.com/b/Ry0Qkx2R)

## Deployed URL and access instructions

The D1 prototype is preserved as a local Godot project under [`Godot/archive/d1_demo`](Godot/archive/d1_demo). View the [video walkthrough](https://youtu.be/zg4K3fiQjJw) or use the archived project's README to run it. The finished product will be distributed as a local Godot add-on, with Python packages installed locally for training.

## D3 improvement highlight

Not applicable for D1. This section will summarize the changes made between D2 and D3.
