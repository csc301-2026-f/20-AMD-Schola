# Installing and distributing the Godot plugin

Schola is a native plugin installed into a Godot project. Our dev and release/prod environments are distribution channels, with separate destinations and revision selection; they are not hosted application servers.

## Channels and package contents

| Channel | Trigger | Destination | Revision |
| --- | --- | --- | --- |
| Dev | Push to `main`; required PR checks also build candidate packages | Successful [Godot Actions run](https://github.com/csc301-2026-f/20-AMD-Schola/actions/workflows/godot.yml), under Artifacts | The run's source commit, recorded in `BUILD.txt` |
| Release/prod | Scheduled D4 publisher or manual dispatch from `main` | [D4 GitHub release](https://github.com/csc301-2026-f/20-AMD-Schola/releases/tag/D4) | The publisher's source commit, pinned by the D4 tag |

The same reusable `godot-packages.yml` builds the packaged extensions in debug and release configurations, extracts the archive into a clean project, and verifies the native classes load with the pinned Godot editor. Upload occurs after this check succeeds. The D4 publisher waits for every packaging platform and refuses to move an existing D4 tag to another commit.

Archives are named:

- `Schola-Godot-windows-x86_64.zip`
- `Schola-Godot-linux-x86_64.zip`
- `Schola-Godot-macos-arm64.zip`

Each contains:

```text
addons/schola/
  plugin.cfg                 Editor plugin entry
  schola.gdextension         Runtime extension descriptor
  schola_plugin.gd           Editor dock
  space_inspector.gd         Resource Inspector
  components/                Reusable sensors, actuators, and shaders
  ui/                        Episode monitor
  bin/<platform>/            Debug/release runtime and ONNX Runtime library
licenses/onnxruntime/         ONNX Runtime license and third-party notices
licenses/godot-cpp/           godot-cpp license
LICENSE.txt                  Schola license
INSTALL.md                   This guide
BUILD.txt                    Source commit, platform, architecture, package scope
```

Windows and Linux x86_64 ZIPs also include:

```text
addons/schola_training/
  schola_training.gdextension  Registers ScholaTrainingConnector
  bin/<platform>/              Debug/release training libraries with static gRPC
python/                        Schola wheel from the same commit
licenses/grpc/                 gRPC and bundled dependency notices
```

macOS arm64 includes the runtime and editor addon. The pinned prebuilt gRPC packages and the supported Python training workflow cover Windows and Linux. The ZIPs leave out the Godot editor, Python interpreter, and trainer dependencies such as PyTorch, Stable-Baselines3, and Ray. Install Godot and Python separately, then install the trainer extra you use. The training libraries already contain native gRPC and Protocol Buffers, so the headers, static archives, and code generators are only needed for source builds. Example scenes, policies, and tests live in the repository so developers can choose what to add to their own projects.

## Install into your project

1. Use Godot 4.7.2 and download the archive matching your operating system and CPU. When downloading from Actions, extract the artifact wrapper first to obtain the plugin ZIP.
2. Close Godot. Extract the plugin ZIP outside your project, then copy `addons/schola/` into your project's `addons/`. Keep `LICENSE.txt`, `licenses/`, and `BUILD.txt` with your distribution records.
3. Open the project. Godot imports `schola.gdextension` and loads the platform's debug runtime. Enable **AMD Schola** under **Project Settings > Plugins** to show the Schola dock and Inspector tools.
4. Confirm native types such as `ScholaEnvironment`, `ScholaAgent`, and `ScholaOnnxPolicy` are available. Follow the repository README's workflows to create an environment or run an ONNX policy.

## Train from the Windows or Linux package

1. With Godot closed, also copy `addons/schola_training/` into your project's `addons/`. Install and update both addons from the same ZIP.
2. In an active Python 3.12 virtual environment, run the command below from the extracted ZIP directory. Replace `<wheel-filename>` with the filename in `python/`. Use `[rllib]` in place of `[sb3]` for RLlib. Pip installs the selected trainer and other Python dependencies.

   ```sh
   python -m pip install "./python/<wheel-filename>.whl[sb3]"
   ```

3. Add `ScholaTrainingConnector` to your training scene, run the scene, then connect the Python trainer as described in [Train with Python](../README.md#train-with-python). The packaged binaries and wheel replace the source build and editable install steps in that guide.

To update, close Godot and replace the installed addon directories with the ones from the new archive. If you train, upgrade the wheel in the same Python environment with `pip install --force-reinstall --no-deps` and the new wheel path, then run the install command with your trainer extra to resolve any dependency changes. Retain the previous ZIP and `BUILD.txt` to roll back. Preserve your environment scenes and models outside the addon directories.

## Export a game

Include the runtime descriptor, matching release library, ONNX Runtime dependency, component scripts used by your scenes, and policy model. The descriptor declares the native dependency for Godot's exporter. Include `.onnx` files in the export preset's non-resource include filter if Godot does not select them automatically. Exclude `addons/schola_training/` and training-only scenes from an inference-only game.

The package check establishes clean-project runtime loading. It does not certify every user's exported game, renderer, camera configuration, or trained policy; verify your own export on its target platform.

## Build and test a package locally

From a source checkout on Linux x86_64, install the native dependencies and build both configurations with the [supported toolchain](../README.md#supported-toolchain):

```sh
python Godot/tools/setup_onnxruntime.py
python Godot/tools/setup_grpc.py
scons -C Godot schola schola_training platform=linux target=template_debug
scons -C Godot schola schola_training platform=linux target=template_release
python Godot/tools/package_plugin.py --platform linux --arch x86_64 --output Godot/build/Schola-Godot-linux-x86_64.zip
```

Use `platform=windows` on Windows. The packager uses `pip wheel --no-deps` to build the Python wheel on Linux and Windows. On macOS, skip gRPC setup, use `platform=macos arch=arm64`, and build `schola` alone. Match the packager arguments to the build. Inspect the resulting archive and install it into a separate clean project before distributing it. CI automates the native installation check for each package platform.

## Troubleshooting

- **Missing native classes:** check Godot version, platform/architecture, the extension descriptor, and that the complete `bin/<platform>/` directory was copied. Read the editor's first native-library error before investigating scene scripts.
- **Missing ONNX Runtime:** restore the complete plugin package; copying only the Schola native library is insufficient.
- **Missing training connector:** on Windows or Linux x86_64, check that both addon directories were installed from the same ZIP. Use a current ZIP if yours predates training support. The macOS ZIP includes the runtime and editor addon.
- **Model does not load:** check that the file exists and matches the agent's effective observation/action spaces, including stacking and recurrent state. Read the model-loading diagnostic.
- **Python cannot connect:** start the training scene first, use the same localhost port in Python and Godot, and connect within `start_timeout_sec`. See [training configuration](../README.md#train-with-python).
- **Headless import crashes after completing:** the known Godot first-import shutdown issue can require a retry. CI retries the known crash codes up to three times and fails persistent errors.
- **Actions artifact expired:** use the versioned D4 release package, or select a newer successful dev run. Keep the package's `BUILD.txt` when reporting an installation issue.
