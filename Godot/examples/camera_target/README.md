# Camera target example

An agent turns to face a red ball that it can only see through its camera. It
shows US11's `ScholaCameraSensor` composed with a US8 rotation actuator, with no
custom sensor or actuator code.

## Files

| File | Contents |
| --- | --- |
| `scenes/camera_target.tscn` | The room, the ball and the agent; the root is the `ScholaEnvironment` |
| `scenes/camera_target_inference.tscn` | The example with `ScholaInferenceStepper` and a timer that moves the ball every 3 seconds |
| `scenes/camera_target_train.tscn` | The example with `ScholaTrainingConnector` for training from Python |
| `scripts/camera_target_environment.gd` | Reset, ball placement and reward |
| `train.py` | Starts the training scene, checks the camera pipeline, trains Stable-Baselines3 PPO and exports ONNX |

## Agent

- **Observation** `00000000:Camera`: a float32 `[3, 64, 64]` RGB image in `[0, 1]`,
  read from the `Agent/View` SubViewport. A `RemoteTransform3D` keeps the
  viewport's camera on the agent's body.
- **Action** `00000000:Rotation`: a yaw change of -10 to 10 degrees per step.
- **Reset**: the agent faces forward and the ball appears 4 m away, within ±30°.
- **Reward**: how directly the agent faces the ball, from -1 to 1. Episodes are
  truncated after 100 steps.

The camera returns the most recently drawn frame. An observation can precede the
latest action, multiple steps can reuse a frame, and the delay is not fixed to one
physics tick. Reset observations can still show the previous episode. US11 keeps
this behavior; an optional render-synchronized lifecycle is future work.
The camera needs a
rendering display: in headless mode it reports a configuration error, and while
the window is minimized no frames are drawn and the image stays black.

## Run

Open `Godot/project.godot`, open
`res://examples/camera_target/scenes/camera_target_inference.tscn`, and press
**F6**. The stepper loads a policy exported for this example's spaces from
`policies/camera_target.onnx`; without it, the stepper reports that the model
cannot be read. Train one as described below.

## Train

Training needs a visible Godot window, because the camera does not render in
headless mode. From the repository root:

```sh
python Godot/examples/camera_target/train.py --godot godot --smoke --steps 100000
```

The script starts the training scene at a fixed 60 Hz, connects on port 8000
(`--port` changes it) and trains Stable-Baselines3 PPO with a CNN on the camera
image. The image is already in `[0, 1]`, so the CNN is told not to divide it by
255. `--smoke` first drives 300 steps and checks that every image is
`[3, 64, 64]`, finite, in `[0, 1]` and not black, that turning moves the ball in
and out of view, and that episodes end. A checkpoint is saved every 25,000
steps, and the final policy as `policies/camera_target.zip` and
`policies/camera_target.onnx`, which the inference scene loads. Policies are not
committed.

Keep the window visible while training: a minimized window draws no frames, so
the camera image stays black.
