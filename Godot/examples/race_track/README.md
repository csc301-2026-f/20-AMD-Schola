# RaceTrack example (US13 draft)

A Godot port of AMD's [RaceTrack example](https://github.com/GPUOpen-LibrariesAndSDKs/ScholaExamples/tree/main/Content/Examples/RaceTrack): a car learns to drive around a track. It is the US13 production example: it will train through Schola's Python tools over gRPC and run the exported ONNX policy in Godot with Python closed.

The track, start position, spaces, observations, actions, reward, and episode rules were read from AMD's Unreal assets: the Blueprints' compiled code and default values, the `RaceTrackTrain` map, and the car's C++ source.

## Status

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
| `scripts/race_track_agent.gd` | Observation and action | `RaceTrackAgent` |
| `scripts/race_track_environment.gd` | Reset, reward, and episode end | `RaceTrackEnvironment` |

## Track and car

- The track is 19-point spline, about 1 km long, with a 10 m wide road. One point that sat 13 cm below the ground in AMD's map is set to ground level, so the road stays visible.
- The car starts 0.7 m behind the track's start and 8.2 m left of its centre line, as placed in map.
- The car weighs 1500 kg, steers its front wheels up to 40°, and drives its rear wheels. Its engine force and brakes are estimates and need tuning.

## Spaces

| | Space |
|---|---|
| Observation | Box of 10, each from -100000 to 100000 |
| Action | Box of 2, each from -1 to 1 |

**Observation**, all in the car's own frame, ordered forward, right, up:

1. The closest point on the track centre, divided by 5 m (values 1-3).
2. The track direction at that point (values 4-6).
3. The car's velocity, divided by 2 m/s (values 7-9).
4. Always 0 (value 10).

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

Open `Godot/project.godot`, open `scenes/race_track_inference.tscn`, and run it (F6). Without `policies/race_track.onnx`, the stepper reports that the model cannot be read.

Once the connector lands, training will use Schola's commands:

```sh
schola sb3 train ppo editor
schola sb3 export --policy-checkpoint-path <CHECKPOINT> --output-path Godot/examples/race_track/policies/race_track.onnx --algorithm PPO
```
