# Code-defined spaces (US15)

Open `main.tscn` and press **F6**. The scene displays and prints successful
initialization, definition, resets, and steps, then remains open for inspection.
The default setup runs two episodes of three steps. It uses the production
`ScholaTrainingHost` API locally; no Python process, network connection, ONNX
model, test driver, or `integration_tests=yes` build is required.

Build and command-line run instructions are in the [Godot guide](../../README.md#code-defined-spaces-example).

## Scene and scripts

```text
CodeDefinedSpaces (Node)              main.gd: runs the local session
├── Environment (ScholaEnvironment)   robot_environment.gd: resets and rewards
│   └── Robot (ScholaAgent)           robot_agent.gd: definitions and values
├── TrainingHost (ScholaTrainingHost)
└── Status (Label)
```

The agent leaves both Inspector space fields empty. Its `_define_spaces()` builds:

```text
observation: Dict
├── camera: Box [480, 640, 3], uint8, bounds 0–255
└── limbs: Dict
    └── limb_0 … limb_1: Dict
        └── joint_0 … joint_2: Dict
            ├── angle: Box [1], bounds -PI–PI
            └── contact: MultiBinary(1)

action: Dict
├── movement: Box [3], bounds -1–1
└── limbs: Dict
    └── limb_0 … limb_1: Dict
        ├── joints: Dict
        │   └── joint_0 … joint_2: Discrete(3)
        └── gripper: MultiBinary(1)
```

Helpers and loops build repeated resources from the agent's exported camera,
limb, and joint settings. A single RGB Box represents 921,600 bounded channel
values; individual pixels do not need separate resources. Scalar bounds broadcast
across the declared shape. Dict keys use the existing canonical sorted ordering.

## Declaration versus sensor data

`_define_spaces()` declares expected structure, dimensions, dtype, and bounds.
`_observe()` separately supplies a synthetic orange RGB buffer and changing joint
values. The flat camera buffer uses HWC order (R, G, B for each pixel) and
`PackedFloat32Array`, matching the current native Box value representation even
when the declared dtype is uint8. Values remain whole numbers within 0–255.

This example does not capture a `Camera3D`, render a robot, run physics, or train
a model. `_act()` records validated actions and advances the synthetic sample.
The status display deliberately avoids printing expanded bounds and pixel data.

## Configuration and lifetime

Select Robot to see the **Spaces defined in code** notice. Callback definitions
override both Inspector assignments, including invalid assignments. Returned
resources do not populate the saved fields. Warning checks inspect metadata and
never run the callback; malformed definitions fail during initialization.

Stop the scene, edit camera dimensions or limb/joint counts in the Inspector,
then press F6 to create a fresh session. Do not change the structure while the
session is running. Successful definitions remain cached across resets and
repeated consumers; the example verifies one callback invocation across both
episodes. See the [API guide](../../docs/us15_space_definition_api.md) for the full
contract, constructors, inherited callbacks, retry rules, and Inspector fallback.

To try a validation failure, change the movement returned by `sample_action()`
from `[0.5, 0, -0.5]` to `[2, 0, 0]` and rerun. The step should fail before
`_act()` receives that action. Restore the valid value afterward.
