# RaceTrack example (US13 draft)

A Godot port of AMD's [RaceTrack example](https://github.com/GPUOpen-LibrariesAndSDKs/ScholaExamples/tree/main/Content/Examples/RaceTrack): a car learns to drive around a track. It is the US13 production example: it will train through Schola's Python tools over gRPC and run the exported ONNX policy in Godot with Python closed.

The original example was derived from AMD’s Unreal assets. This local version deliberately changes course size, vehicle handling, and starting position for an arcade driving demo.

## Local component demo

Open this worktree's `Godot/project.godot`, then open
`res://examples/race_track/scenes/component_demo.tscn` and press F6.
W applies throttle, S applies brakes, A/D steer, and R resets the episode.
Above 7 m/s (about 25 km/h), tap S while turning to initiate a mild drift.
Rear grip and lateral stabilization ease down, with a small capped yaw assist;
release the brake and keep steering to sustain it. Straighten out for 0.25 s
or slow below 4.5 m/s to recover grip smoothly. Drift yaw assistance is stronger
than normal cornering, with a 2 rad/s assist limit. The HUD shows drift
blend percentage, and small fading dust puffs behind the rear tires show when
they are sliding on the ground. Drift thresholds, grip fractions and yaw assist are Inspector
settings on the car’s `arcade_vehicle.gd` script.
The mechanic reads physics control properties, so policy actions trigger it too.
The HUD shows native host steps, speed, track observations, velocity, and reward.
This is a keyboard controller through `ScholaTrainingHost`, not a trained policy.
The keyboard scene disables off-track, tilt, and step-limit endings; press R to
reset. The training scene retains configurable episode limits.

The agent composes child nodes in this order:

1. **Track** (`ScholaPathSensor3D`): six track-relative floats, from a reusable sensor accepting any `Path3D`.
2. **Velocity** (`ScholaVelocitySensor3D`): three velocity floats from the reusable add-on.
3. **Controls** (`ScholaVehicleActuator3D`): two actions, with the original vehicle
   steering/throttle/brake gain and smoothing. Also reusable in other vehicle scenes.

The agent script only handles placement/reset. It has no `_observe` or `_act`
overrides, so the native adapter dispatches the child components.

A deterministic headless check drives 360 native steps, checks observation shapes, acceleration, turning, upright stability
and vehicle motion, and verifies brake-triggered drift and that reset clears velocity and all controls:

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
| `../../addons/schola/components/path_sensor_3d.gd` | Track-relative observation component | Track features |
| `scenes/component_demo.tscn` | Keyboard controller and live component HUD | Local inspection |
| `scripts/race_track_environment.gd` | Reset, reward, and episode end | `RaceTrackEnvironment` |

## Track and car

- Course control points and handles use 45% of the original dimensions; road
  width stays 10 m so the car still has room to turn. The loop ends at its start.
- Both road edges have 1.2 m tall, 0.5 m thick solid walls, sampled every 1.5 m
  with overlapping collision boxes. The start is on the centerline.
- The 900 kg car has a shorter body, low center of mass, damped suspension,
  grounded lateral grip and speed-dependent downforce. Pitch and roll are locked
  for predictable flat-track arcade handling, while yaw and collisions remain physical.
  This intentionally does not model banked tracks, loops, or realistic aerial rotation.
- Full normalized input is 1, steering is limited to 28 degrees, and steering
  reduces to 25% at 18 m/s. Engine force fades toward a 28 m/s top speed.
  Braking remains available at that speed. Suspension and grip are scene/script settings.
- `arcade_vehicle.gd` owns grounded grip; the reusable actuator owns controls,
  optional speed-sensitive steering and optional engine speed limiting. These
  speed options default to disabled for other scenes.

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

Inputs are normalized in [-1, 1] and smoothed before reaching the physics body.
The keyboard supplies full throttle/brake or steering; speed-sensitive steering
limits abrupt high-speed direction changes.

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
