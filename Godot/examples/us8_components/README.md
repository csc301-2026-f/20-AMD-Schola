# US8 component playground

Open `res://examples/us8_components/main.tscn` in the main Godot project and press
**F6** (Run Current Scene). This is an example inside `Godot/project.godot`, not a
separate project or a frozen milestone demo. The native runtime extension must
be built; no Python trainer, model, or integration-test build is needed.

On this Linux workspace, launch it directly from the repository root:

```sh
/home/guneev/Desktop/University/CSC301/Godot_v4.7.2-stable_linux.x86_64 \
  --path Godot res://examples/us8_components/main.tscn
```

Or open the editor:

```sh
/home/guneev/Desktop/University/CSC301/Godot_v4.7.2-stable_linux.x86_64 \
  --editor --path Godot res://examples/us8_components/main.tscn
```

If rebuilding is needed, close Godot first (native extension reload is disabled):

```sh
.venv/bin/scons -C Godot schola platform=linux target=template_debug -j4
```

## Try it

- **WASD / arrow keys** move the green body around orange obstacles.
- **Space** or the toggle button enables a simple scripted controller. It moves
  forward and sidesteps close obstacles using the previous native ray observation.
  This is a hand-written controller, not a trained policy.
- **R** or Reset restores the starting position through Schola's episode reset.
- Cyan lines show the three rays; red lines stop at collision points. The HUD
  shows the action and actual native observations: front, left, and right each
  return a hit flag and a distance normalized to their six-meter range.

The scene uses real component composition:

```text
US8Components
├── Host (ScholaTrainingHost)
└── Environment (ScholaEnvironment + environment.gd)
    └── Agent (ScholaAgent, no direct observation/action overrides)
        ├── Body (CharacterBody3D)
        │   ├── Front (RayCast3D)
        │   ├── Left (RayCast3D)
        │   └── Right (RayCast3D)
        ├── RaySensor (ScholaSensor + ray_cast_sensor_3d.gd)
        └── Movement (ScholaActuator + movement_actuator_3d.gd)
```

`main.gd` sends controller actions through `ScholaTrainingHost.step()`. The native
agent adapter dispatches to the GDScript movement actuator, collects the GDScript
ray sensor values, and returns the observation used by the HUD and controller.
The scene then calls `move_and_slide()`; observations therefore describe the
world before that frame's movement. Nothing calls component hooks directly.

## Change the components

Select **RaySensor** to change its ray paths or open its GDScript. Select
**Movement** to change its maximum speed or open its GDScript. These are the
runtime add-on's reusable implementations under `addons/schola/components/`.
The controller uses the actuator's current `maximum_speed`, so changing that
Inspector value changes movement speed without editing controller code.
You can also attach your own GDScript extending either native base node.

This playground expects one sensor with three rays and one movement actuator.
Its HUD and automatic controller use that six-value observation layout. Adapt
`main.gd` when changing that layout. Stop and rerun the scene after changing
spaces or component membership: the training session fixes its definition at
initialization. See [the API guide](../../docs/us8_components.md).

## Headless smoke check

From the repository root:

```sh
/home/guneev/Desktop/University/CSC301/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path Godot res://examples/us8_components/main.tscn \
  --fixed-fps 60 --quit-after 240 -- --us8-smoke
```

Expect `US8_SMOKE_OK: native composition, movement, and ray hits verified` and
exit code zero. This drives 90 native steps and checks movement, at least one ray
hit, and the observation layout. The frame limit bounds startup failures; a zero
exit code without the success message does not establish a passing smoke check.
