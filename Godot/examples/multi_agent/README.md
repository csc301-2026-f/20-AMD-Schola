# US12 multi-agent example

Two agents walk a number line from 0 to 9 in one `ScholaEnvironment`, trained
together through `ScholaTrainingConnector` by Schola's Python trainer.

| Agent | Action space | Observation space |
|---|---|---|
| `runner` | `Discrete(3)`: back, stay, forward | `Box(2)`: own and partner position, 0..1 |
| `hopper` | `MultiDiscrete([2, 2])`: back button, forward button, each 0 or 1 | `Discrete(10)`: own position |

- An agent's episode ends when it reaches 9 (`terminated`) or after
  `max_steps` steps (`truncated`). Agents can finish on different steps; a
  finished agent stops acting, and the episode ends when both are done.
- `reward_mode` on the `Environment` node selects `individual` rewards (each
  agent's own progress, with a bonus at the goal) or `shared` rewards (both
  get the team average).
- Each result's `info` carries `agent`, `position`, and `episode`, so Python can
  check that every result reached the right agent.

The hopper's buttons use `MultiDiscrete` rather than `MultiBinary` because
RLlib has no action distribution for `MultiBinary` and stops before training.

Because the agents' spaces differ, train with RLlib, which gives each agent its
own policy. Schola's SB3 wrapper requires every agent to share one observation
and action space.

## Train on Windows

Run from the repository root in a developer shell, with the repository's
Python environment active (`pip install -e "Resources/python[rllib]"` if
Schola's Python package is not installed yet).

1. Install the committed gRPC package and build both extensions:

   ```powershell
   python Godot\tools\setup_grpc.py
   scons -C Godot platform=windows target=template_debug
   ```

2. Import the project once, then start the scene headless. It prints
   `Schola: waiting for Python to connect to 127.0.0.1:8000.` and waits
   45 seconds for Python:

   ```powershell
   godot --headless --path Godot --import
   godot --headless --path Godot res://examples/multi_agent/main.tscn
   ```

3. In a second shell, train with RLlib PPO against the running game:

   ```powershell
   schola rllib train ppo --timesteps 4000 editor --port 8000
   ```

`godot` stands for the path to your Godot 4.7 executable. Schola's Python CLI
does not start on macOS: `schola/core/utils/ubt.py` rejects the platform when
it is imported.
