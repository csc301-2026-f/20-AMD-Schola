# Verification of the Godot workflows

Checked on November 26, 2026 against main at [`090ef506f4a16c0e92c328743dfb5264f997903b`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/090ef506f4a16c0e92c328743dfb5264f997903b). Local checks used Windows x86_64, MSVC, Godot 4.7.2, Python 3.12, and the repository's pinned native dependencies.

## Automated build, tests, and installation

The [main CI run](https://github.com/csc301-2026-f/20-AMD-Schola/actions/runs/45760521033) passed its required gate. The build/test job ran core, inference, transport, and Godot integration suites. Separate Linux x86_64, Windows x86_64, and macOS arm64 jobs built the runtime packages, loaded each extracted package in a clean project, and uploaded the 3 dev artifacts.

| Local check | Result |
| --- | --- |
| Runtime and training debug extensions, `integration_tests=yes` | Both rebuilt successfully |
| Catch2 core | 135 cases, 1,632 assertions passed |
| Catch2 inference | 43 cases, 775 assertions passed |
| Catch2 transport | 23 cases, 241 assertions passed |
| GdUnit4 integration | 380 cases across 28 suites: 371 executed, 9 skipped, 0 failures/errors/orphans |
| Dependency installer/build-target Python tests | 21 tests passed |
| Code-defined spaces example | 2 episodes, 6 actions, each space hook called once |

The 9 skipped integration cases require a rendering display: 7 camera-capture cases, 1 native camera-render case, and 1 real-camera inference case. The headless camera configuration, image-format, fake-camera, and inference checks ran. Rendered Windows Compatibility/Mobile results are recorded separately in [US11](user_stories/US11.md). A headless pass does not establish renderer coverage.

Run the native checks from a Visual Studio developer shell at the repository root:

```powershell
scons -C Godot platform=windows target=template_debug integration_tests=yes -j4
scons -C Godot unit_tests inference_tests transport_tests platform=windows target=template_debug integration_tests=yes -j4
./Godot/build/tests/schola_core_tests.exe
./Godot/build/tests/schola_inference_tests.exe
./Godot/build/tests/schola_transport_tests.exe
python -m unittest discover -s Godot/tools -p 'test_*.py'
godot --headless --path Godot --import
godot --headless --path Godot -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/integration
godot --headless --path Godot res://examples/code_defined_spaces/main.tscn -- --us15-smoke-test
```

Test prerequisites are a writable temporary directory, writable Godot user-data storage, and localhost socket access for gRPC tests.

## Real Python trainers

| Workflow | Result on the checked main revision |
| --- | --- |
| Number-line example, RLlib PPO, 2 heterogeneous agents | 4,096 environment steps, 299 completed environment episodes, both policies trained, successful exit |
| Same scene with a native 3-observation Box stack on `runner` | 4,096 environment steps, 288 completed environment episodes, both policies trained, successful exit |
| RaceTrack, Schola SB3 wrapper and production connector | 600 smoke steps, 5 episode endings, finite observations/rewards; then 1,024 PPO training steps and ONNX export |
| Newly exported RaceTrack policy in native inference | 120 physics frames with no inference failures, after the Python training process exited |

The RLlib episode counts come from `env_runners.num_episodes_lifetime` in the final result, not the number of agent trajectories. PPO collected 4,096 steps for the requested 4,000-step budget. The unstacked run's final mean episode length was 9.77 steps; the stacked run's was 10.2. Short runs establish that training updates and episode handling work; they are not substitutes for the production example's learning benchmark.

The unstacked command is documented in the [number-line example](../examples/multi_agent/README.md):

```sh
schola rllib train ppo --timesteps 4000 editor --port 8000
```

For the stacked check, the same scene and command were used with this configuration applied before the scene entered the tree. The runner's effective Box changed from 2 values to 6; the hopper retained its Discrete observation and MultiDiscrete action. The stack was native Godot preprocessing, not a Python frame-stack wrapper.

```gdscript
var scene = load("res://examples/multi_agent/main.tscn").instantiate()
var stacker := ScholaStacker.new()
stacker.stack_size = 3
stacker.add_new_dimension = false
scene.get_node("Environment/Runner").observation_adapters = [stacker]
```

Local runner scripts and logs were kept under ignored `Godot/build/`; the committed policy was preserved. The RaceTrack smoke used the existing `train.py` connection helpers, `schola.sb3.VecEnv`, `VecMergeDictActionWrapper`, PPO settings, and Schola ONNX exporter, with its output redirected to that temporary directory. The newly exported model was assigned to the production inference scene's `ScholaOnnxPolicy` for playback. For the maintained end-user training/export command, follow [RaceTrack checks](../examples/race_track/README.md#checks).

## Learning and playback

The committed policy and untrained baseline were rerun through `demo_check.gd`, without Python:

| Policy | Demo map | Average speed | Dropped obstacles | Random layouts |
| --- | --- | --- | --- | --- |
| Untrained | 61 m, 0 laps, 0 contacts | 2 km/h | 0/30 | 0/10 |
| Committed trained policy | 1,811 m, 2 laps, 0 contacts | 58 km/h | 30/30 | 10/10 |

The trained run passed the evaluator's thresholds and recorded 67.9 seconds of drifting. The untrained car failed all run-ups before the obstacle appeared; its lack of contacts is not successful driving. The checked run agrees with the documented learning outcome. Fixed-step evaluation makes comparisons repeatable under the same setup; exact floating-point/physics measurements can differ across builds and platforms.

```sh
godot --headless --path Godot --fixed-fps 60 -s res://examples/race_track/demo_check.gd -- res://examples/race_track/policies/race_track_untrained.onnx res://examples/race_track/policies/race_track.onnx
```

[US13](user_stories/US13.md) also preserves the earlier seed-7/seed-42 training comparison. Those 100,352-step runs improved over the baseline but did not complete a lap; they are separate from the longer-trained committed policy.

## Review evidence and bounded limitations

- [PR #50](https://github.com/csc301-2026-f/20-AMD-Schola/pull/50) merged RaceTrack. Its early PR body describes an initial draft; the merged scenes, scripts, component registrations, model files, and evaluation are the current implementation.
- [PR #61 review](https://github.com/csc301-2026-f/20-AMD-Schola/pull/61#issuecomment-7080933005) already recorded Windows RLlib training over 4,096 steps and 300 episodes. The [follow-up approval](https://github.com/csc301-2026-f/20-AMD-Schola/pull/61#pullrequestreview-6014638956) followed the reconnect test's Windows timeout correction. The current rerun above independently confirms training on main; its episode count differs because training is stochastic.
- [PR #60 review](https://github.com/csc301-2026-f/20-AMD-Schola/pull/60#pullrequestreview-6068493049) approved the visible-viewport and image-format fixes. Camera capture uses the latest completed rendered frame, including potentially pre-action or previous-episode images. Render synchronization is a future feature, not an unfinished part of that contract.
- [PR #93](https://github.com/csc301-2026-f/20-AMD-Schola/pull/93) merged the independent space hooks. PRs #97, #98, and #100 merged the unpublished-agent ID reuse fixes; #99 applied the host error-message contract. They are included in the checked revision.
- [PR #67 review](https://github.com/csc301-2026-f/20-AMD-Schola/pull/67#pullrequestreview-6012913875) distinguishes the delivered metadata reader from the shared RLlib export limitation. Current `Resources/python/schola/rllib/export.py` still supplies a Python list as `seq_lens` in the old-policy path; the attention export cases remain disabled in `Test/rllib/test_export_to_onnx.py`. A direct export check using RLlib's old-stack `PPOTorchPolicy` with LSTM reproduced `AttributeError: 'list' object has no attribute 'shape'` when RLlib read `seq_lens.shape[0]`. The sequence-dimension fixture uses Schola's exporter with a small `ScholaModel` subclass. This does not establish a trainer-exported attention/sequence policy; see [US14](user_stories/US14.md).

Runtime package loading, in-editor inference, and exported-game playback have separate coverage. Platform package loading passed in CI; [US7](user_stories/US7.md) records Windows debug/release game exports. This record adds current native playback and trainer checks. Camera learning benchmarks, broader rendered-platform coverage, and a trainer-produced sequence-dimension fixture are extension opportunities.

## Coverage of the project specification and D4 handout

| Requirement | Submission documentation and evidence |
| --- | --- |
| Separate the existing AMD product from the team's Godot contribution | [Root README: scope and architecture](../../README.md#problem-and-project-scope); [module map](maintenance.md) |
| Define environments and agents with engine-native tools | [Node/resource configuration](../README.md#inspect-the-schola-ui), [US1](user_stories/US1.md), [US5](user_stories/US5.md), and [code-defined spaces](../examples/code_defined_spaces/README.md) |
| Modular observations/actions and the step/reset loop | [Component guide](../README.md#reusable-sensors-and-actuators), [US4](user_stories/US4.md), and host/component integration suites |
| Reuse the shared Schola protocol and Python trainers | [Training setup](../README.md#train-with-python), SB3 and RLlib runs above, [US3](user_stories/US3.md) |
| Simultaneous agents and independent/shared rewards | [Number-line example](../examples/multi_agent/README.md), [US12](user_stories/US12.md), heterogeneous-policy trainer results above |
| A production example demonstrates successful learning | [RaceTrack](../examples/race_track/README.md), trained/untrained evaluation above, [US13](user_stories/US13.md) |
| Run trained policies inside gameplay without Python | [Inference and export guide](us7_inference_api.rst), current ONNX playback above, [US7](user_stories/US7.md) |
| Current workflows, installation, and user access | [Root README](../../README.md), [D4 release](https://github.com/csc301-2026-f/20-AMD-Schola/releases/tag/D4), [installation/update/rollback guide](distribution.md) |
| Automatic dev and release/prod distribution | [Distribution channels](distribution.md#channels-and-package-contents), [required CI](../../.github/workflows/godot.yml), [platform packaging](../../.github/workflows/godot-packages.yml), [D4 publisher](../../.github/workflows/d4-release.yml) |
| Reliable automated core and frontend-facing tests | Native suites plus Godot scene, Inspector-warning, dock/monitor, and integration tests; [passing CI](https://github.com/csc301-2026-f/20-AMD-Schola/actions/runs/45760521033) |
| Software quality, NFR evidence, and architecture decisions | [README NFR section](../../README.md#non-functional-requirements), [development contract](development_contract.md), [architecture and decisions](../../README.md#architecture-and-decisions) |
| New-contributor setup and partner maintenance/handoff | [Developer setup](../README.md#build-and-run), [maintenance guide](maintenance.md), [contribution workflow](../../CONTRIBUTING.md) |
| D3 process and resource discipline continue | Required PR/merge-queue gate, teammate reviews linked above, job timeouts, concurrency cancellation, cached native builds, and explicit dependency-rebuild workflows |

The specification's optional headless work is supported for nonvisual training; real camera capture requires a rendering display. The native C++ GDExtension implementation is the agreed Godot port; the handout's C# preference does not describe the submitted architecture. The D4 presentation uses these documents for its technical walkthrough and partner-access references; its live delivery and Q&A are assessed separately from repository documentation.
