# Composing agents from sensors and actuators (US8)

`ScholaSensor` and `ScholaActuator` are native runtime Node types. Extend either
in GDScript, assign its `space` resource and optional `component_id`, and implement
`_observe() -> Variant` or `_act(action: Variant) -> void`. A blank identifier uses
the node's name. Identifiers must be unique within each component kind on an agent.
Optional `_get_component_errors() -> PackedStringArray` supplies configuration
errors used by both the Inspector and the runtime adapter.

A `ScholaAgent` collects descendants in depth-first scene-tree order, stopping at
nested agents. Each side composes independently. Overriding the agent's `_observe`
or `_act` takes precedence for that side and uses its explicitly assigned space;
without an override, descendant components supply a dictionary space and values.
With no components, the existing explicit-space/direct-hook API still applies.

Dictionary keys are `00000000:<id>`, `00000001:<id>`, and so on. Index prefixes
preserve component order through Schola's canonical dictionary sorting and Python
flattening. Obtain the current keys from `agent.observation_space.spaces` and
`agent.action_space.spaces`. Reordering, renaming, inserting, deleting or changing
component spaces after initialization requires defining/initializing the agent
again. Training environments initialize only once, so recreate the environment
and its training session when changing the interaction definition. IDs, object identities, and spaces are checked before dispatch. The adapter
validates the whole action before any component receives it. Callbacks run on the
Godot main thread. Components should not change the agent's structure during a
callback; action callbacks are not transactional and prior world changes cannot
be rolled back if a later callback fails.

The runtime add-on includes these reusable GDScript implementations:

- `ScholaRayCastSensor3D`: assign an ordered array of paths to `RayCast3D` nodes.
  Use property assignment or `add_ray(path)` to synchronize the paths and space.
  Raw in-place array edits bypass the setter; a mismatched shape is reported as a
  configuration error and rejected at runtime. Reassign `sensor.rays = sensor.rays`
  after such edits. For training, recreate the environment/session before
  initializing with the new spaces: an environment adapter initializes only once. Each ray contributes `[hit, normalized_distance]`, bounded in `[0,1]`. A miss
  contributes `[0,0]`. The sensor forces a fresh query; collision masks and body
  exclusions belong to each ray. At least one nonzero-length ray is required.
- `ScholaMovementActuator3D`: assign a `CharacterBody3D` path and positive finite
  `maximum_speed`. Three continuous values set local X/Y/Z velocity, transformed
  using the body's rotation. The body's physics loop owns `move_and_slide()`,
  gravity and collision response. Actions use speed units, not normalized input.

For example, a custom discrete sensor beside a `CharacterBody3D` named `Body`
under the agent can use:

```gdscript
extends ScholaSensor

func _init() -> void:
    var discrete := ScholaDiscreteSpace.new()
    discrete.n = 2
    space = discrete

func _observe() -> Variant:
    return int(get_node("../Body").is_on_floor())
```

Unreal Schola's sensor/actuator components define spaces and collect observations
or apply actions. These nodes provide the same division of responsibility using
Godot descendants and GDScript virtual hooks. Both combine named subspaces into
one interaction definition. The ray sensor implements Unreal's hit flag and
normalized hit-distance fields without optional tracked-tag channels. Movement
uses Godot's local X/Y/Z axes and CharacterBody velocity rather than Unreal's
pawn input accumulation. Camera observations are outside US8.

Run the native adapter and physics checks with the integration-test runtime build
and `res://tests/integration/components_test.gd`, using the commands in the Godot
README. No frozen milestone demo is required or modified.

## Velocity and vehicle components

- `ScholaVelocitySensor3D`: `body_path` accepts `RigidBody3D` (including
  `VehicleBody3D`) or `CharacterBody3D`. Returns three linear velocity values.
  `local_frame` defaults to true; disable for world coordinates. `axes` defaults
  to Godot X/Y/Z; option 1 returns forward/right/up for vehicles facing +Z.
  Values are divided by a finite positive `velocity_scale` (default 1 m/s).
  The Box is unbounded so high speeds are not silently clipped.
- `ScholaVehicleActuator3D`: `body_path` targets a `VehicleBody3D`. Two normalized
  actions control steering and signed throttle/brake. Exported limits, gain and
  rise/fall rates retain the RaceTrack defaults. Positive steering turns right
  for the example's +Z-facing car. Call `reset()` when resetting an episode to
  clear smoothing state and all three physics control properties.

The [RaceTrack component demo](../examples/race_track/README.md) combines these
with a track-specific sensor. Its agent has no direct observation/action hooks.
