# RaceTrack example (US13 draft)

A Godot port of AMD's [RaceTrack example](https://github.com/GPUOpen-LibrariesAndSDKs/ScholaExamples/tree/main/Content/Examples/RaceTrack): a car learns to drive around a track. It is the US13 production example: it will train through Schola's Python tools over gRPC and run the exported ONNX policy in Godot with Python closed.

The track, start position, spaces, observations, actions, reward, and episode rules were read from AMD's Unreal assets: the Blueprints' compiled code and default values, the `RaceTrackTrain` map, and the car's C++ source.

## Local component demo

Open this worktree's `Godot/project.godot`, then open
`res://examples/race_track/scenes/component_demo.tscn` and press F6.
W applies throttle, S applies brakes, A/D steer, and R resets the episode.
The HUD shows native host steps, speed, track observations, velocity, and reward.
This is a keyboard controller through `ScholaTrainingHost`, not a trained policy.
Episode endings automatically reset the car using the existing track rules.

The agent composes child nodes in this order:

1. **Track** (`RaceTrackSensor`): six track-relative floats, specific to this example.
2. **Velocity** (`ScholaVelocitySensor3D`): three velocity floats from the reusable add-on.
3. **Controls** (`ScholaVehicleActuator3D`): two actions, with the original vehicle
   steering/throttle/brake gain and smoothing. Also reusable in other vehicle scenes.

The agent script only handles placement/reset. It has no `_observe` or `_act`
overrides, so the native adapter dispatches the child components.

A deterministic headless check drives 120 native steps, checks observation shapes
and vehicle motion, and verifies that reset clears velocity and all controls:

```sh
godot --headless --path Godot res://examples/race_track/scenes/component_demo.tscn -- --race-track-smoke
```

## Training and inference status

- **Inference** works once a model exists at `policies/race_track.onnx`.
- **Training** is not possible yet. Python reaches the scene only through the `ScholaTrainingConnector` node from US3, which is not implemented.

## Files

| File | Contents | AMD's equivalent |
|---|---|---|
| `scenes/race_track.tscn` | Ground, track curve, and road | The track and road in each map |
| `scenes/car.tscn` | The car, its wheels and camera, and its `ScholaAgent` | `RaceTrackAgent`, a `SportsCar` |
| `scenes/race_track_train.tscn` | Track, a `ScholaEnvironment` with the car, and `ScholaTrainingHost` | `Maps/RaceTrackTrain` |
| `scenes/race_track_inference.tscn` | Track, car, and `ScholaInferenceStepper` | `Maps/RaceTrackInference` |
| `scripts/track.gd` | Distance along the track, closest centre point, direction, and start position | `RaceTrackSpline` |
| `scripts/race_track_agent.gd` | Placement and reset of the composed agent | `RaceTrackAgent` |
| `scripts/track_sensor.gd` | Track-relative observation component | Track features |
| `scenes/component_demo.tscn` | Keyboard controller and live component HUD | Local inspection |
| `scripts/race_track_environment.gd` | Reset, reward, and episode end | `RaceTrackEnvironment` |

## Track and car

- The track is 19-point spline, about 1 km long, with a 10 m wide road. One point that sat 13 cm below the ground in AMD's map is set to ground level, so the road stays visible.
- The car starts 0.7 m behind the track's start and 8.2 m left of its centre line, as placed in map.
- The car weighs 1500 kg, steers its front wheels up to 40°, and drives its rear wheels. Its engine force and brakes are estimates and need tuning.

## Spaces

| | Space |
|---|---|
| Observation | Dict: `00000000:Track` → Box(6), `00000001:Velocity` → Box(3) |
| Action | Dict: `00000000:Controls` → Box(2), bounded [-1, 1] |

**Observation**, all in the car's own frame, ordered forward, right, up:

1. The closest point on the track centre, divided by 5 m (values 1-3).
2. The track direction at that point (values 4-6).
3. The car's velocity, divided by 2 m/s (values 7-9).
The old trailing constant zero is removed. Track features retain bounds of
[-100000, 100000]; velocity is unbounded and divided by 2 m/s.

**Policy compatibility:** these dictionary spaces replace the original flat Box
spaces. Train and export a fresh policy for this layout; old ONNX policies are
not assumed compatible. Renaming or reordering components also changes the layout.

**Action:**

1. Steering; positive turns right.
2. Throttle when positive, brake when negative.

Both are multiplied by 100, so small values already give full input. The inputs then move gradually toward that target, like Unreal's car physics does. The smoothing rates are estimates and are not verified.

## Episode and reward

- **Reset:** the car returns to its start and stops.
- **Terminated:** the car is 10 m or more from the track centre, or rolled more than 10°. The reward for that step is -10.
- **Truncated:** after 500 steps.
- **Reward on other steps:** `0.01 * exp(-(distance from centre / 5 m)^2)` plus the metres moved along the track.

AMD's Blueprint updates its stored track distance before computing progress, so its progress reward is always 0. This example rewards progress instead.

## Running

Open `Godot/project.godot`, open `res://examples/race_track/scenes/race_track_inference.tscn`, and run it (F6). Without `policies/race_track.onnx`, the stepper reports that the model cannot be read.

Once the connector lands, training will use Schola's commands:

```sh
schola sb3 train ppo editor
schola sb3 export --policy-checkpoint-path <CHECKPOINT> --output-path Godot/examples/race_track/policies/race_track.onnx --algorithm PPO
```
