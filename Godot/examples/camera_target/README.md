# Camera target example

An agent turns to face a red ball that it can only see through its camera. It
shows US11's `ScholaCameraSensor` composed with a US8 rotation actuator, with no
custom sensor or actuator code.

## Files

| File | Contents |
| --- | --- |
| `scenes/camera_target.tscn` | The room, the ball and the agent; the root is the `ScholaEnvironment` |
| `scenes/camera_target_inference.tscn` | The example with `ScholaInferenceStepper` and a timer that moves the ball every 3 seconds |
| `scripts/camera_target_environment.gd` | Reset, ball placement and reward |

## Agent

- **Observation** `00000000:Camera`: a float32 `[3, 64, 64]` RGB image in `[0, 1]`,
  read from the `Agent/View` SubViewport. A `RemoteTransform3D` keeps the
  viewport's camera on the agent's body.
- **Action** `00000000:Rotation`: a yaw change of -10 to 10 degrees per step.
- **Reset**: the agent faces forward and the ball appears 4 m away, within ±30°.
- **Reward**: how directly the agent faces the ball, from -1 to 1. Episodes are
  truncated after 100 steps.

The camera returns the most recently drawn frame, so an observation can trail the
latest action by one frame, as with Unreal's camera sensor. The camera needs a
rendering display: in headless mode it reports a configuration error, and while
the window is minimized no frames are drawn and the image stays black.

## Run

Open `Godot/project.godot`, open
`res://examples/camera_target/scenes/camera_target_inference.tscn`, and press
**F6**. The stepper loads a policy exported for this example's spaces from
`policies/camera_target.onnx`; without it, the stepper reports that the model
cannot be read.
