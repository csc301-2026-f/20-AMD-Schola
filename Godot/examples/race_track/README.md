# RaceTrack example

A Godot port of AMD's [RaceTrack example](https://github.com/GPUOpen-LibrariesAndSDKs/ScholaExamples/tree/main/Content/Examples/RaceTrack): a car learns to drive around a track. It is the [US13](../../docs/user_stories/US13.md) production example: it trains through Schola's Python tools over gRPC and runs the exported ONNX policy in Godot with Python closed.

The original example was derived from AMD's Unreal assets. This version deliberately changes course size, vehicle handling, and starting position for an arcade driving demo, and adds hills, jumps and obstacles that the original course does not have. The car sees the obstacles with a ray sensor.

## Quick start: watch the trained policy

1. Build both native extensions using the setup in the [Godot README](../../README.md#build-and-run).
2. Open `Godot/project.godot` in Godot 4.7.2.
3. Open `res://examples/race_track/scenes/race_track_inference.tscn` and press F6.

The car drives with the committed policy, `policies/race_track.onnx`, which is stored with Git LFS. Python is not needed.

Press 1, 2, 3 or 4 to switch between the untrained, 25,000-step, 350,000-step and final policies while the car drives, and R to put the car back at the start. Click the left, middle or right of the screen to drop an obstacle into that lane 50 m ahead of the car; it disappears once the car has passed it. Right-click any obstacle to remove it, including the ones on the map, or press Delete to remove the last one dropped. R clears dropped obstacles and brings back removed map obstacles.

## Results

`evaluate.gd` drives the inference scene for one 50-second episode without Python and reports the metres driven along the track.

The committed policy was trained from scratch with `train.py` for 350,000 steps, then for 300,000 more with `--resume` after touching an obstacle began ending episodes and the drift bonus rose to 0.5. Over a 3-minute drive it completes 4.5 laps without touching an obstacle and drifts for about 31 seconds.

| Policy | Distance in 50 s | Laps |
|---|---|---|
| Committed policy (`policies/race_track.onnx`) | 1108.4 m | 1.22 |
| Random actions (seeded uniform steering and pedal) | 58.6 m | 0.06 |
| Untrained exported fixture (`tests/inference/fixtures/schola_ppo_race_car.onnx`) | 20.2 m | 0.02 |

All three stayed on the track. Physics runs at a fixed 60 Hz, so repeated runs give the same numbers. Reproduce them from the repository root:

```sh
godot --headless --path Godot --fixed-fps 60 -s res://examples/race_track/evaluate.gd
```

Pass ONNX paths, or `random`, after `--` to score other policies:

```sh
godot --headless --path Godot --fixed-fps 60 -s res://examples/race_track/evaluate.gd -- res://examples/race_track/policies/race_track.onnx random
```

The script exits with status 1 if a policy cannot run. In CI, `tests/integration/race_track_inference_test.gd` checks that the inference scene points at the committed policy and drives the car with a Schola-exported stand-in policy.

## Train your own policy

### Set up Python

Install the training dependencies from the repository root with Python 3.12, then import the project once:

```sh
# Linux and macOS
uv venv --python 3.12 Godot/.venv
uv pip install --python Godot/.venv/bin/python -e 'Resources/python[sb3]'
godot --headless --path Godot --import
```

```powershell
# Windows
uv venv --python 3.12 Godot\.venv
uv pip install --python Godot\.venv\Scripts\python.exe -e "Resources/python[sb3]"
godot --headless --path Godot --import
```

In the commands below, Windows users replace `Godot/.venv/bin/python` with `Godot\.venv\Scripts\python.exe`.

### Train and export

From the repository root:

```sh
Godot/.venv/bin/python Godot/examples/race_track/train.py --godot godot --headless --steps 100000
```

The script launches the training scene, connects on localhost port 8000, and trains Stable-Baselines3 PPO with the composed dictionary observations and actions. Each action advances one physics frame at a fixed 60 Hz.

Training episodes start at random points on the track, and each one gets a new random obstacle layout so the policy has to react to what its sensors report instead of memorizing the map. One layout in five has almost no obstacles (0-2), almost half have 3-8 single obstacles, and the rest are busier, with up to 12 single obstacles. Some of the busier layouts also contain clusters of two to four gates 16-22 m apart, where each gate blocks two of the three lanes and the open lane switches sides, so the car has to slow to about 40 km/h or less to weave through. Every layout keeps obstacles at least 25 m apart outside clusters, away from the first 45 m and last 15 m of the lap, and clear of the 30 m before and 45 m after each jump. Turn off `random_obstacles` on the training scene's environment to train on the fixed map instead.

Every 25,000 steps, and once at the end, the script starts a second copy of the scene on the next port (8001) and test-drives the current policy from the start line without random actions on five 50-second episodes: the demo map that the inference scene shows, then four random layouts (seeds `test_drive_layout_seed` to `test_drive_layout_seed` + 3, 0 by default). They are the same in every test drive, so scores can be compared, and averaging them keeps one lucky or unlucky layout from deciding which policy is kept. The score is the average training reward of those drives: mostly the metres driven along the track before each episode ends, with up to 50% more for metres driven while drifting, and -10 if it ends in a crash. A policy that drifts can therefore beat one that drives slightly farther without drifting. Each test drive also prints the metres driven and how long the car drifted. Training is noisy, so a later policy can drive worse than an earlier one. Only a policy that beats the best score so far is saved, as `race_track.zip` and `race_track.onnx` under `policies/`, so you can stop training at any time and keep the best policy. Before each test drive the current policy is also saved as `race_track_latest.zip` and `race_track_latest.onnx`, whatever its score, so a long run is never lost.

Saving replaces the committed `race_track.onnx`; `git restore Godot/examples/race_track/policies/race_track.onnx` brings it back. The script closes its Godot processes when training finishes or fails.

Options:

- `--port N` uses ports N and N+1 instead of 8000 and 8001.
- `--godot PATH` points at Godot when it is not on PATH as `godot`.
- Omit `--headless` to watch; each test drive then opens its own window.
- `--attach` trains a scene you started yourself instead of launching one. Test drives still open their own Godot, so `--godot` is still needed.

### Train from the editor

Open `race_track_train.tscn` and press F6. Its `EditorTrainer` node starts `train.py --attach` with the Python in `Godot/.venv`, `.venv` or `venv` at the repository root, or `python` on PATH. It adds `--resume` when `policies/race_track.zip` exists, so training continues from your best policy. Python's output appears in the Output panel, and closing the game window stops Python. Set the number of training steps in the node's `steps` property; the default is 100,000.

The scene runs at normal game speed, about 55 steps per second, so this is several times slower than `--headless`. The training connector waits up to 300 seconds (`step_timeout_sec`) for Python's next step, long enough for a test drive in its own window.

### Run the exported policy

Open `race_track_inference.tscn` and press F6, or score it with `evaluate.gd` as in [Results](#results).

### Continue training

Continue training the saved best policy rather than starting over:

```sh
Godot/.venv/bin/python Godot/examples/race_track/train.py --godot godot --headless --resume --steps 300000
```

`--steps` is the number of additional training steps when resuming. `--resume latest` continues from `race_track_latest.zip` instead of the best policy. The saved policy is test-driven first, and a new policy replaces the best one only if it scores higher. Resuming needs `race_track.zip` from your own training run; only the ONNX model is committed.

## Checks

A short training run checks the whole Python pipeline. It first runs 600 gRPC steps and checks for finite observations and rewards, acceleration, and episode autoreset. It then performs a short PPO update, test-drives the result and exports ONNX. It does not show that the policy has learned to finish a lap.

```sh
Godot/.venv/bin/python Godot/examples/race_track/train.py --godot godot --headless --smoke --steps 1024
```

A deterministic handling check drives the keyboard demo for 360 native steps. It checks observation shapes, acceleration, turning, upright stability and vehicle motion, and verifies brake-triggered drift and that reset clears velocity and all controls.

```sh
godot --headless --path Godot --fixed-fps 60 res://examples/race_track/scenes/component_demo.tscn -- --race-track-smoke
```

The integration tests `race_track_inference_test.gd`, `race_track_training_scene_test.gd` and `vehicle_components_test.gd` under `Godot/tests/integration/` check the inference scene, the training scene's configuration and spaces, and the reusable sensors and actuator. The training-scene suite needs the training extension and is skipped without it.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Cannot get class 'ScholaTrainingConnector'` or `'ScholaInferenceStepper'` when a scene opens | The native extensions are missing or out of date. Rebuild both with the default SCons target in the [Godot README](../../README.md#build-and-run). `ScholaTrainingConnector` comes from the training extension, which needs the gRPC package. |
| `train.py` cannot find Godot | Pass `--godot` with the full path to the Godot executable. On Windows, use the `_console.exe` build so Godot's output appears in the terminal. |
| `train.py` cannot connect, or the connector reports that the port is in use | Another process holds port 8000 or 8001. Pass `--port` with a free port; test drives use the next one. |
| `ScholaTrainingConnector: ...` error after 45 seconds | Godot waited `start_timeout_sec` (45 s by default) for Python to connect. Start the scene through `train.py`, or press F6 on `race_track_train.tscn` and check the Output panel for Python errors. |
| The policy cannot load, and `policies/race_track.onnx` is only a small text file | The policy is stored with Git LFS and has not been downloaded. Run `git lfs install` and `git lfs pull` from the repository root. |
| The inference scene reports `inference_failed`, or the policy's spaces do not match | The ONNX model was trained for a different observation or action layout. Renaming, reordering or reconfiguring the Track, Velocity, Rays or Controls components, or changing the look-ahead distance, needs a newly trained policy. |
| `--resume` fails to find `race_track.zip` | Only the ONNX model is committed. Train once without `--resume` first. |

## Keyboard demo

Open `res://examples/race_track/scenes/component_demo.tscn` and press F6. W applies throttle, S applies brakes, A/D steer, and R resets the episode. This is a keyboard controller through `ScholaTrainingHost`, not a trained policy. The HUD shows native host steps, speed, track observations, velocity, and reward.

Above 7 m/s (about 25 km/h), tap S while turning to start a mild drift. Rear grip and lateral stabilization ease down, with a small capped yaw assist; release the brake and keep steering to sustain it. Straighten out for 0.25 s or slow below 4.5 m/s to recover grip smoothly. Drift yaw assistance is stronger than normal cornering, with a 2 rad/s assist limit. The HUD shows the drift blend percentage, and small fading dust puffs behind the rear tires show when they are sliding. Drift thresholds, grip fractions and yaw assist are Inspector settings on the car's `arcade_vehicle.gd` script. The mechanic reads physics control properties, so policy actions trigger it too.

The keyboard scene disables off-track, tilt, stall, and step-limit endings; press R to reset. The training scene keeps its configurable episode limits.

## How the agent is composed

The agent composes child nodes in this order:

1. **Track** (`ScholaPathSensor3D`): six track-relative floats sampled 10 m ahead of the car, from a reusable sensor accepting any `Path3D`.
2. **Velocity** (`ScholaVelocitySensor3D`): three velocity floats from the reusable add-on.
3. **Rays** (`ScholaRayCastSensor3D`): 25 rays, one every 5° across 120° and 30 m long, from the front bumper that show walls and obstacles, from the reusable add-on. Like a driver's eyes, they only see in straight lines, so obstacles behind a bend stay hidden until the car is in it; on average an obstacle is first seen about 27 m ahead.
4. **RoadAhead** (`RaceTrackRoadAheadSensor`): three values, one per lane (left, middle, right), giving the distance along the road to the next obstacle in that lane divided by 60 m, or 1 when the lane is clear for 60 m. It follows the road around bends and over hills, which the rays cannot, so the car can plan for obstacles about 2.4 s ahead at 90 km/h. It reads every visible, solid node in the `obstacle` group, so it also reports obstacles that viewers drop and ignores ones they removed.
5. **Controls** (`RaceTrackControls`): two actions through the reusable `ScholaVehicleActuator3D`, with the original vehicle steering/throttle/brake gain and smoothing. It also keeps the last action for the on-screen action display.

The agent script only handles placement and reset. It has no `_observe` or `_act` overrides, so the native adapter dispatches the child components.

## Files

| File | Contents | AMD's equivalent |
|---|---|---|
| `scenes/race_track.tscn` | Ground, track curve, road, embankment, and obstacle positions | The track and road in each map |
| `scenes/car.tscn` | The car, its wheels and camera, and its `ScholaAgent` | `RaceTrackAgent`, a `SportsCar` |
| `scenes/race_track_train.tscn` | Track, a `ScholaEnvironment` with the car, and `ScholaTrainingConnector` | `Maps/RaceTrackTrain` |
| `scenes/race_track_inference.tscn` | Track, car, and `ScholaInferenceStepper` | `Maps/RaceTrackInference` |
| `scenes/component_demo.tscn` | Keyboard controller and live component HUD | Local inspection |
| `scenes/action_display.tscn`, `scripts/action_display.gd` | On-screen steering wheel, pedals and speed showing the agent's actions | None |
| `scripts/obstacle_dropper.gd` | Drops an obstacle 50 m ahead of the car when the viewer clicks, and removes obstacles on right-click | None |
| `scripts/road_ahead_sensor.gd` | Distance to the next obstacle in each lane along the road ahead | None |
| `scripts/model_switcher.gd` | Switches the inference scene between four policies with keys 1-4 and restarts the car with R | None |
| `scripts/track.gd` | Distance along the track, closest centre point, direction, start positions, walls, obstacles and random obstacle layouts | `RaceTrackSpline` |
| `scripts/race_track_agent.gd` | Placement and reset of the composed agent | `RaceTrackAgent` |
| `scripts/race_track_environment.gd` | Reset, reward, and episode end | `RaceTrackEnvironment` |
| `scripts/race_track_controls.gd` | The car's vehicle actuator, which also keeps the last action | None |
| `scripts/evaluation.gd`, `evaluate.gd` | Python-free policy scoring and the random-action baseline | None |
| `train.py` | PPO training, test drives, best-policy saving, and ONNX export | None |
| `scripts/editor_trainer.gd` | Starts `train.py` when the training scene is played from the editor | None |
| `../../addons/schola/components/path_sensor_3d.gd` | Track-relative observation component | Track features |

## Track and car

- Course control points and handles use 90% of the original dimensions, so one lap is about 905 m; road width stays 10 m. The loop ends at its start.
- The elevation changes along the lap: a flat start straight; a 6 m hill whose crest is 203 m from the start; a dip back to ground level at 252 m; a climb onto a section 4 m up on an embankment from 314 m to 494 m, including the hairpin; a long curving descent back to ground level by 587 m; and a 3 m hill whose crest is at 803 m. The steepest slope is about 12°. An embankment under the road holds it up, and the road has collision.
- Two yellow jump ramps span the road, 1.4 m tall and 6 m long: one at the crest of the 6 m hill (196 m) and one on a flat straight (600 m). At 22 m/s the car is in the air for about 1 s. The ramps are listed by distance along the track in the Track node's `jumps` property.
- Five orange obstacles, 2.5 m wide and 1 m tall, block one half or the middle of the road at 325, 350, 475, 685 and 788 m. They are listed as (distance along the track, sideways offset to the left) in the Track node's `obstacles` property, and they are in the `obstacle` group that the Rays sensor reports. The inference scene uses this fixed map; the training scene replaces it with a random layout every episode.
- Both road edges have 1.2 m tall, 0.5 m thick solid walls, sampled every 1.5 m with overlapping collision boxes. The start is on the centerline.
- The 900 kg car has a shorter body, low center of mass, damped suspension, grounded lateral grip and speed-dependent downforce. Roll is locked for predictable arcade handling; pitch is free so the car follows the hills and jumps. The suspension is stiff enough for the downforce at speed, and the body's collision box sits 0.2 m above the visible body, so the car does not scrape the road at the bottom of slopes. This intentionally does not model banked tracks, loops, or realistic aerial rotation.
- Full normalized input is 1, steering is limited to 28 degrees, and steering reduces to 25% at 18 m/s. Engine force fades toward a 28 m/s top speed. Braking remains available at that speed. Suspension and grip are scene/script settings.
- `arcade_vehicle.gd` owns grounded grip; the reusable actuator owns controls, optional speed-sensitive steering and optional engine speed limiting. These speed options default to disabled for other scenes.

## Spaces

| | Space |
|---|---|
| Observation | Dict: `00000000:Track` → Box(6), `00000001:Velocity` → Box(3), `00000002:Rays` → Box(75), `00000003:RoadAhead` → Box(3) |
| Action | Dict: `00000000:Controls` → Box(2), bounded [-1, 1] |

The untrained, 25,000-step, 350,000-step and 650,000-step policies were trained when the car had nine rays, 15° apart, and no RoadAhead sensor. Every third of today's 25 rays points in the same direction as one of those nine, so each of these ONNX models was converted by adding a step that passes only those rays to the original network and an unused RoadAhead input; they drive exactly as before.

**Observation**, all in the car's own frame, ordered forward, right, up:

1. The point on the track centre 10 m ahead of the closest point, divided by 5 m (values 1-3).
2. The track direction at that point (values 4-6).
3. The car's velocity, divided by 2 m/s (values 7-9).
4. Nine rays from the front bumper, 30 m long and spread over 120° from left to right (values 10-36). For each ray: whether it hit an obstacle, whether it hit anything, and the hit distance as a fraction of 30 m (0 when nothing is hit). The rays are drawn on screen, green where they hit something and red where they don't.

Looking 10 m ahead lets the car see a corner before it reaches it. With only the closest point, the car noticed the hairpin too late to brake and got stuck on its wall. Track features keep bounds of [-100000, 100000]; velocity is unbounded; ray values are in [0, 1].

**Action:**

1. Steering; positive turns right.
2. Throttle when positive, brake when negative.

Inputs are normalized in [-1, 1] and smoothed before reaching the physics body. Speed-sensitive steering limits abrupt high-speed direction changes.

**Policy compatibility:** these dictionary spaces replace the original flat Box spaces, so policies trained for AMD's Unreal example are not compatible. Policies trained before the Rays sensor was added are not compatible either. Renaming, reordering or reconfiguring components changes the layout, and changing the look-ahead distance changes what the track values mean; both need a newly trained policy.

## Episode and reward

- **Reset:** the car returns to its start and stops. In the training scene it starts at a random point instead, at least 30 m before the next obstacle, so every part of the track gets practice. Test drives (started with `--race-track-start-line`) and the inference scene start at the start line.
- **Terminated:** the car is `maximum_track_distance` or more from the track centre, tilted more than `maximum_tilt_degrees`, or touching an obstacle while `terminate_on_obstacle` is on. With contact monitoring on, the car's body touching a wall also counts as off the track, so a car turned sideways against a wall cannot sit there with its centre still inside the limit. The reward for that step is -10. The training scene uses 4.5 m, so touching a wall ends the episode, and 60°, so hills and jumps don't. It turns `terminate_on_obstacle` on and enables contact monitoring on its car, so touching an obstacle ends the episode at once instead of after two seconds stuck.
- **Training episodes:** truncated after 3000 steps (50 simulated seconds). Two seconds without forward progress ends the episode with -10, so a car stuck at an obstacle resets.
- **Reward on other steps:** `0.01 * exp(-(distance from centre / 5 m)^2)` plus the metres moved along the track, multiplied by `1 + drift_bonus * drift amount`. `drift_bonus` is 0.5 and the drift amount goes from 0 to 1, so drifting pays up to 50% more per metre, but only while the car moves forward; a drift that loses distance never pays. Each step's info reports `progress` and `drift`, which `train.py` prints for each test drive. Progress wraps at the start/finish line, so completing a lap does not produce a track-length penalty.

AMD's Blueprint updates its stored track distance before computing progress, so its progress reward is always 0. This example rewards progress instead.

## Action display

The training and inference scenes show the agent's latest action in the bottom-left corner: a steering wheel that turns with the steering action, and brake and gas pedals that fill with the pedal action. It shows the action the model chose, before the car smooths it. During training, PPO adds random exploration, so the wheel and pedals jump between steps; the trained policy in the inference scene moves them smoothly.
