# D3 demo

The [D2 demo](../d2)'s grid world, rebuilt on the current Schola GDExtension and drawn in 2D:
1. Godot sends observations and rewards to a local Python trainer.
2. Godot applies the trainer's actions to the agent.
3. The trained policy is exported to ONNX and runs in Godot with Python closed.

## What changed since D2

D2 used GDScript stand-ins for most of the environment and lifecycle. D3 replaces them with the native implementations:

| Area | D2 | D3 |
| --- | --- | --- |
| US1 environment and agent | `ScholaDemoEnvironment` and `ScholaDemoAgent` scripts with their own `step()` and `reset_episode()` | `GridEnvironment` and `GridAgent` extend the native `ScholaEnvironment` and `ScholaAgent` directly and implement only the US1 hooks (`_reset_episode`, `_get_reward`, `_is_terminated`, `_is_truncated`, `_get_info`, `_observe`, `_act`) |
| US4 episode lifecycle | `demo_runner.gd` stepped the environment itself | One native `ScholaTrainingHost` session runs every reset and step, whether the action comes from the keyboard, Python or the ONNX policy |
| Seeding | The demo seeded its own RNG | The US1 adapter seeds `get_rng()` from the reset request |
| Truncation | `max_episode_steps` on the environment node | An exported `max_episode_steps` used by `_is_truncated()` with `get_episode_step()`, as US5 specifies |
| US7 inference | `initialize_spaces()` and stateless `infer()`, plus a GDScript Q-table reader | `ScholaOnnxPolicy` resource on the `Runner` with `initialize(agent)`, a `ScholaPolicyState` per agent that resets each episode, and `infer(observation, state)`. The GDScript Q-table reader is gone |
| Export | Included the Q-table JSON | Exports only `*.onnx` and excludes `addons/schola_training/*`, as the US7 guide requires |

US3's gRPC transport is not implemented yet, so the JSON-over-TCP `ScholaLocalConnector` and the Q-learning `python/trainer.py` remain stand-ins. They follow the [local protocol](../../docs/local_protocol.md). `demo_runner.gd` plays the part of US3's `ConnectorLoop`. It turns each Python request into a host `reset()` or `step()` call.

### Host session rules

These follow from the current US1 and US4 contracts:

- An environment node initializes only once, so the scene runs a single host session for its whole life. That session uses `DISABLED` auto-reset. A trainer that asks for `SAME_STEP` or `NEXT_STEP` is refused with `INCOMPATIBLE`.
- A failed host step closes the whole session. The runner therefore checks each Python action against the agent's action space before stepping. A bad action ends only the Python connection.
- If the session does close, the panel shows **CLOSED**, and **Reload** starts a new session.

## Requirements

- Godot 4.7.2
- Python with `gymnasium`, `numpy`, `onnx`, and `onnxruntime`. Install them into a virtual environment with `python -m pip install gymnasium numpy onnx onnxruntime`.

## Run

1. Download ONNX Runtime, build the extension, and copy both libraries into the demo:
   ```sh
   python Godot/tools/setup_onnxruntime.py
   scons -C Godot platform=windows target=template_debug
   mkdir -p Godot/demo/d3/addons/schola/bin/windows
   cp Godot/addons/schola/bin/windows/schola.windows.template_debug.x86_64.dll Godot/addons/schola/bin/windows/onnxruntime.dll Godot/demo/d3/addons/schola/bin/windows/
   ```
   `ScholaTrainingHost` is part of the runtime extension, so the demo does not need the `schola_training` add-on.
2. Optional: create the reference policy so **Policy** works before any training:
   ```sh
   python Godot/demo/d3/python/create_reference_policy.py
   python Godot/demo/d3/python/export_onnx.py
   ```
3. Open `Godot/demo/d3/project.godot` in Godot.
4. On the `Runner` node, set `python_executable` to a Python that has the packages above, for example `.venv/Scripts/python.exe`.
5. Press F5 or the Play button.

## Parallel training

### Parallel viewer

Press **Parallel training ›** in the main panel (or run `demo/parallel.tscn`) to manage parallel training from one window:

- **Instances**, **Episodes**, and **Steps/s each** have − / + buttons. The instance count goes up to 16 or your CPU's logical core count, whichever is larger. It starts at 4, or at the core count if that is lower. Settings are locked while a run is active.
- **Start** launches `train_parallel.py` with the running Godot executable. It uses the viewer's `python_executable`, `python` by default.
- **Stop** asks the trainer to save and end the run. **Back** returns to the main scene.
- Every instance appears as a live mini board, in a near-square grid. A board flashes green, red or orange when an episode ends, and shows "no signal" if its instance stops reporting.
- The panel shows how many instances are live, the shared trainer's episode count and ε, the overall success rate, the combined steps/s, and the reward history.

The instances remain separate headless processes, so they still simulate in parallel; the viewer only draws them. Each instance sends one small UDP report per frame to `127.0.0.1:9100` (the viewer's `viewer_port`), and the viewer's Stop sends `stop` back. Launcher and trainer output goes to `python/logs/parallel.log`.

### Command line

`python/train_parallel.py` runs classic synchronous parallel training. It starts N copies of the scene, each a separate Godot process with its own `ScholaTrainingHost` session, port, and CPU core. One trainer then learns from all of them:

```sh
python Godot/demo/d3/python/train_parallel.py --godot <path/to/godot> --instances 4 --episodes 1200
```

- The instances run headless. Add `--windowed` to watch each one in its own window, tiled two per row.
- Every round, the trainer sends one action to each instance at the same time and waits for all of them. It then updates a single shared Q-table.
- An instance whose episode ends is reset in the same round, so none sits idle. `--episodes` counts episodes across all instances.
- At the end, the trainer saves `policies/q_policy.json`, exports `policies/q_policy.onnx`, and closes every session. The instances then quit. Each instance's output is in `python/logs/godot_<port>.log`.
- Ports run from `--base-port` (default 8000) upward. The launcher refuses to start if any of them is in use.
- `--speed` caps steps per second per instance. The default is 2000 headless and 60 windowed.

Measured on a 20-thread Windows laptop, 1200 episodes:

| Instances | Steps/s | Speed-up |
| --- | --- | --- |
| 1 | 472 | 1.0× |
| 4 | 1410 | 3.0× |
| 8 | 2369 | 5.0× |

The instances simulate in parallel, but each round waits for the slowest one. Gains flatten once the instance count passes the number of free cores.

Each instance takes these options after `--` on the Godot command line. You can also start instances by hand and run `python python/trainer.py --port 8000 8001 ...`.

| Option | Effect |
| --- | --- |
| `--port=N` | Listen for the trainer on port N; also shown in the window and panel title |
| `--speed=N` | Steps per second |
| `--train` | Listen as soon as the scene starts, without launching a trainer |
| `--quit-after-training` | Quit when the training session ends |
| `--viewer=N` | Report this instance's board to the parallel viewer on UDP port N |

This is the demo's stand-in for parallel training. The JSON connector and the tabular learner remain stand-ins until US3's gRPC transport lets Stable-Baselines3 or RLlib drive several Godot instances.

## Smoke check

After building and copying the runtime extension, import the project and run the headless check:

```sh
godot --headless --path Godot/demo/d3 --editor --quit
godot --headless --path Godot/demo/d3 -s res://tests/d3_smoke.gd
```

The check drives the scene through its own `ScholaTrainingHost` session, without Python. It verifies:

- the scene configuration, agent ID, spaces, and 40-step limit;
- seeded resets;
- the goal, hazard, and timeout outcomes and their rewards;
- that an ONNX policy at `policies/q_policy.onnx` loads and produces valid actions, when that file exists.

## Controls

- **Arrow keys:** move the agent while in manual mode.
- **Train:** Godot listens on `127.0.0.1:8000` and launches `python/trainer.py`. The trainer connects and sends every request (start, definition, reset, step), and Godot answers each one through the host.
  - The log panel shows the connection state: `waiting`, `connected`, `training`, `closed` or `error`. An error always comes with a message saying what went wrong.
  - If nothing connects within 45 seconds, the run ends with an error. Check `python_executable` on `Runner`, or untick `auto_launch_trainer` and run `python python/trainer.py --port 8000` yourself.
- **Stop:** the trainer saves `policies/q_policy.json` and exports it to the `Runner` policy's `model_path` (`policies/q_policy.onnx`), and the scene resets.
- **Policy:** reloads the model, checks it against the agent's spaces, and lets it drive the agent with Python closed.
- **Check US2:** logs the US2 errors for a set of invalid actions and observations.
