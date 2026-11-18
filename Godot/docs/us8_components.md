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

Each reusable node below builds its `space` from its exported settings and
rebuilds it when a setting that changes the layout is assigned. The derived
`space` is shown read-only in the Inspector and is not saved in scenes. Changing
a layout setting after initialization has the same redefinition requirement as
any other space change.

The runtime add-on includes these reusable GDScript implementations:

- `ScholaRayCastSensor3D`: observes existing `RayCast3D` nodes, generated rays,
  or both. `rays` lists `RayCast3D` paths, observed first in array order; their
  own masks and exclusions apply. `num_rays` generated rays follow, fanned left
  to right across `ray_degrees` (0-360) around the `-Z` axis of `origin_path`,
  or the nearest `Node3D` ancestor when blank. A 360-degree fan spaces rays
  evenly without duplicating the first. `ray_length`, the local
  `ray_end_offset`, `collision_mask`, `collide_with_bodies` and
  `collide_with_areas` shape each query. `exclude_origin_body` ignores the first
  `CollisionObject3D` at or above the origin. Each ray contributes
  `[group flags..., hit, normalized_distance]`, bounded in `[0,1]`. There is one
  flag per `tracked_groups` entry, set when the hit collider is in that node
  group. A miss contributes zeros. With no tracked groups this is the original
  `[hit, normalized_distance]` layout. Use property assignment or
  `add_ray(path)` to synchronize `rays`/`tracked_groups` with the space. Raw
  in-place array edits bypass the setter; a mismatched shape is reported as a
  configuration error and rejected at runtime. Reassign `sensor.rays = sensor.rays`
  after such edits. For training, recreate the environment/session before
  initializing with the new spaces: an environment adapter initializes only once.
  The sensor forces fresh queries and needs at least one nonzero-length ray.
- `ScholaMovementActuator3D`: assign a `CharacterBody3D` or `RigidBody3D` path.
  `has_x`, `has_y` and `has_z` select the axes, and each enabled axis takes one
  action in `[minimum_speed, maximum_speed]` (default `[-1, 1]`). Each action
  is multiplied by `speed_scale` and sets the velocity along that axis. Axes are
  local to the body's rotation unless `local_frame` is disabled. Disabled axes
  keep the body's current velocity, so gravity can stay with the body. A
  `CharacterBody3D`'s physics loop owns `move_and_slide()` and collision response.
  Actions use speed units, not normalized input.

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
one interaction definition. The ray sensor mirrors Unreal's `NumRays`,
`RayDegrees`, `RayLength`, `RayEndOffset` and `TrackedTags` settings, in the same
per-ray layout. Godot node groups stand in for actor tags, and a collision mask
stands in for the trace channel. Movement mirrors Unreal's per-axis toggles and
`MinSpeed`/`MaxSpeed`/`ScaleValue`. It uses Godot's X/Y/Z axes and sets body
velocity rather than accumulating pawn input. Camera observations are outside US8.

Run the native adapter and physics checks with the integration-test runtime build
and `res://tests/integration/components_test.gd`, using the commands in the Godot
README. No frozen milestone demo is required or modified.

## Velocity and vehicle components

- `ScholaVelocitySensor3D`: `body_path` accepts `RigidBody3D` (including
  `VehicleBody3D`) or `CharacterBody3D`. Returns up to three linear velocity values.
  `local_frame` defaults to true; disable for world coordinates. `axes` defaults
  to Godot X/Y/Z; option 1 returns forward/right/up for vehicles facing +Z.
  `has_x`, `has_y` and `has_z` keep the first, second and third component of the
  selected axes, for example forward speed only.
  Values are divided by a finite positive `velocity_scale` (default 1 m/s).
  With the default `bound` of 0 the Box is unbounded, so high speeds are not
  silently clipped. A positive `bound` declares `[-bound, bound]` and clamps to it.
- `ScholaVehicleActuator3D`: `body_path` targets a `VehicleBody3D`. By default two
  normalized actions control steering and signed throttle/brake. Disable
  `has_steering` for pedal-only control. `pedal_mode` selects one signed `[-1, 1]`
  pedal (default), separate throttle and brake values in `[0, 1]`, or no pedals.
  Exported limits, gain and rise/fall rates retain the RaceTrack defaults.
  Positive steering turns right for the example's +Z-facing car. Call `reset()`
  when resetting an episode to clear smoothing state and all three physics
  control properties.

The [RaceTrack component demo](../examples/race_track/README.md) combines these
with `ScholaPathSensor3D`, which accepts any `Path3D` and reports the closest
point offset and tangent in the observed body frame. Configure `body_path`,
`path_path`, positive `location_scale`, and XYZ or +Z-forward axes.
`look_ahead` samples the point and tangent further along the path; closed
curves wrap. `include_location`, `include_direction` and `include_progress`
choose features, in that order. Progress is the closest offset divided by the
curve length, bounded in `[0, 1]`. `has_x`, `has_y` and `has_z` choose vector
components. Location and direction share a symmetric `bound`, default 100000.
Vehicle `controls_scale` defaults to 1, also used by the arcade race car. `steering_sign` is configurable for wheel orientation. Its agent has no direct observation/action hooks.

`ScholaVehicleActuator3D` also exposes `steering_speed_reference` and `top_speed`
(in m/s). Zero disables each feature. Steering interpolates from full lock at rest
to `minimum_steering_fraction` at the reference speed. Engine force fades to zero
at top speed, without disabling brakes or imposing a hard velocity clamp.
