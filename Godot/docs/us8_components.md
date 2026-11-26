# Composing agents from sensors and actuators (US8)

`ScholaSensor` and `ScholaActuator` are native runtime Node types. Extend either
in GDScript, assign its `space` resource and optional `component_id`, and implement
`_observe() -> Variant` or `_act(action: Variant) -> void`. Blank identifiers use
the node name. Identifiers must be unique within each component kind on an agent.
Optional `_get_component_errors() -> PackedStringArray` supplies configuration
errors used by the Inspector and the runtime adapter.

A `ScholaAgent` collects descendants in depth-first scene-tree order, stopping at
nested agents. Each side composes independently. The agent's `_observe` or `_act`
override takes precedence for that side and uses its explicitly assigned space;
otherwise descendant components supply a dictionary space and values. With no
components, the explicit-space/direct-hook API still applies.

Dictionary keys are `00000000:<id>`, `00000001:<id>`, and so on. Prefixes preserve
component order through canonical sorting and Python flattening. Obtain the keys
from `agent.get_effective_observation_space().spaces` and
`agent.get_effective_action_space().spaces`. The serialized `observation_space`
and `action_space` properties retain only explicitly assigned resources; generated
component dictionaries are never written into those properties when saving a scene. Changing
membership, IDs, order or spaces after initialization requires redefining the
agent. Training environments initialize once; recreate the environment/session.
The adapter validates configuration at definition and caches the component layout
and spaces. Scene, script, ID and resource changes invalidate that check; unchanged
layouts use a constant-time revision check instead of rebuilding spaces on every
observe/act call. Local child structure/order signals track the agent subtree, stopping at nested
agents; unrelated scene-tree churn does not invalidate the layout. Component-wide
warning listeners run only in the editor. User-owned Dict spaces still get polled
because in-place Dictionary edits do not emit resource change signals. Runtime
`_get_component_errors()` hooks run for all components once before each observe/act dispatch, so invalid
sensor configuration is caught before actions run. Each dispatch performs one layout/revision check and one runtime preflight.
Callbacks and diagnostic hooks must not mutate agent structure during dispatch;
changes made by callbacks are validated on the next dispatch.
The whole action is validated before any actuator callback. All callbacks execute on the Godot main
thread. Callbacks must not alter the agent structure. Actions are not
transactional; earlier world changes cannot be rolled back on later failures.

## Reusable actuators

All actuator implementations are scripts in `addons/schola/components/`. Their
spaces are generated from their exported settings. Manual space edits must remain
semantically equivalent; reassign a space-setting property to regenerate them.
Inputs use Godot X/Y/Z order, omitting disabled axes.

| Class | Input and behavior |
| --- | --- |
| `ScholaMovementActuator3D` | Box input sets enabled local velocity axes on a `CharacterBody3D` at `body_path`. `enabled_axes` selects axes. Default symmetric bounds are `[-maximum_speed, maximum_speed]`; set `symmetric_bounds=false` to use `[minimum_speed, maximum_speed]`, including backward-only intervals. `input_scale` scales accepted inputs. Disabled local axes preserve existing velocity, including gravity/jump velocity. |
| `ScholaRotationActuator3D` | Box input applies a local Euler rotation increment to the `Node3D` at `target_path`. `lower_degrees`/`upper_degrees` bound pitch(X), yaw(Y), roll(Z). `normalized_input` accepts `[0,1]` and rescales each enabled axis. Angles use degrees. |
| `ScholaTeleportActuator3D` | MultiDiscrete input applies a world-space position offset to `target_path`. Per-axis Wait/Positive/Negative flags determine choices, in that order. Axes with fewer than two choices are omitted. `step` supplies distances. `sweep=true` requires a physics body and uses `move_and_collide()` to stop at obstacles. `RigidBody3D` targets are rejected because they require a physics integration callback. |

Movement emits `movement_input(local_velocity)` with the scaled input, rotation
emits `rotation_input(delta_degrees)`, and teleport emits `teleport_input(offset)`.
These signals fire before applying the change. Movement's `movement_enabled`
gate skips applying input; `force=true` bypasses that gate, while the signal still
fires for accepted input. The body loop owns `move_and_slide()`, gravity and
collision response. There is no automatic action delta-time multiplier.

Unreal movement accumulates pawn input; Godot sets selected CharacterBody velocity
components. Unreal teleport's implementation adds offsets in world axes, which
this port follows. Euler axes follow Godot conventions rather than Unreal's axis
names. Unreal-specific teleport physics flags are represented by explicit Godot
body types and swept versus direct movement.

## Ray observations

`ScholaRayCastSensor3D` supports two modes:

- Default: assign `rays`, an ordered array of `RayCast3D` paths. Their targets,
  collision settings and exclusions remain native RayCast settings. Use assignment
  or `add_ray(path)` after edits; raw in-place array size changes are rejected
  until synchronized by `sensor.rays = sensor.rays`.
- Generated: enable `use_generated_rays`, assign `origin_path` to a `Node3D`, and
  configure `num_rays`, `ray_degrees`, `ray_length` and `end_offset`. Rays fan left to right
  around local -Z. A single ray faces forward; 360 degrees forms a circle without
  a duplicate endpoint. Unlike Unreal's single-ray edge placement, one Godot ray is centered. The origin transform applies to the ray endpoints, then `end_offset` is
  added in world axes.
  `collision_mask`, `collide_with_areas` and `exclude_paths` configure queries.
  A collision-object origin is automatically excluded; list other bodies explicitly.

Each ray contributes `[tag_0, ..., tag_N, hit, normalized_distance]`, bounded in
`[0,1]`. `tracked_tags` names Godot groups on the hit collider. Each matching group
sets its own flag, so several flags may be set. Misses contribute only zeros.
Without tags the original `[hit,distance]` layout is preserved. Fresh queries run
on observation. Use 1..4096 rays and at most 256 tags. Zero-length, nonfinite and
unsynchronized configurations are rejected.

`draw_debug` displays ray lines using `debug_hit_color` and `debug_miss_color` at
runtime. The editor shows the configured trajectories without querying physics.
Unlike Unreal's optional worker tracing, Godot queries stay on the main thread
under the development contract. Call physics observations during the physics loop;
parallel scene-tree/physics access is not exposed by this component.

## Camera observations

`ScholaFakeCameraSensor` emits image observations without rendering. Configure
`width`, `height` and `enabled_channels` (RGBA flags). `custom_image` supplies a
flattened CHW buffer. Empty buffers produce zeros; short buffers are zero-padded
and excess values are ignored, matching Unreal's fake camera. Consumed values
must be finite and in `[0,1]`.

`ScholaCameraSensor` reads the latest completed frame from configured
`SubViewport` nodes. Choose `capture_mode`:

- Color: `viewport_path`, with selected R/G/B/A channels in that order.
- Depth: `depth_viewport_path`, reading its red channel as normalized linear depth.
  Color channel flags may be zero in this mode.
- ColorDepth: selected color planes followed by one depth plane, using both paths.

The Box space is float32 `[channels, height, width]`, with bounds `[0,1]`. Each
plane is row-major (top to bottom, left to right); there is no resizing or automatic
color-space conversion. Source viewports must exactly match the configured size.
Use dimensions 1..2048, with at most 4,194,304 output values. The real camera
needs at least 2×2, because Godot never makes a SubViewport smaller. Viewports
with HDR 2D enabled are rejected because they produce linear values above 1; use
an LDR source for normalized color.

Supported readback formats are uncompressed `Image.FORMAT_RGB8` and
`Image.FORMAT_RGBA8`. Byte channels become floats in `[0,1]`; RGB8 supplies alpha
as 1 when selected. Compressed, floating-point/HDR, and other image formats are
rejected rather than decompressed or converted. Viewport configuration is checked
before startup; the actual image format is checked when pixels become available
at capture. Unsupported readback returns no observation and fails the runtime
observation validation. The sensor also prints an error naming the format, for
example `ScholaCameraSensor._observe: readback format FORMAT_RGBAH is not
supported`, once until a supported frame arrives, and keeps it in
`readback_error`. The same readback contract applies to the depth viewport.

The lifecycle owner configures the viewport, Camera3D, world and update mode.
Use `SubViewport.UPDATE_ALWAYS` or request an update before the capture frame.
Viewports set to Disabled are rejected because they never draw. When Visible
viewports are allowed but show an Inspector warning: they draw only while
something displays them, such as a `TextureRect`, and otherwise captures repeat
their last frame.
Await `RenderingServer.frame_post_draw` before the first reset/readback. Observations
use the most recent completed render, which can precede the current physics action.
`ScholaTrainingHost.step()` applies actions and reads observations synchronously;
the caller cannot insert an awaited render between those phases. Waiting before
the next host call can provide a newer completed frame, but does not guarantee an
image of the action submitted in that same call. Likewise, waiting before
`reset()` does not guarantee that its observation reflects changes made inside
`_reset_episode()`: the reset hook and observation run in one synchronous call.
US11 deliberately retains this latest-completed-frame behavior for training and
inference. Multiple steps can read the same frame, and the delay is not guaranteed
to be exactly one physics tick. A reset observation can still show the previous
episode; it must not be described as a fresh image of the reset scene.
An optional lifecycle that applies actions or resets, advances simulation, waits
for rendering, and only then collects observations is deferred to a future user
story (see [future opportunities](user_stories/remaining.md)).
Rendering is not forced inside the synchronous sensor callback. Empty/unavailable readback fails; headless display mode reports
a configuration error. Use the fake camera for headless tests or run a real
rendering display, including a GPU-capable virtual display for training.

For rendered depth, the add-on supplies `linear_depth.gdshader`: apply it as a
`ShaderMaterial` override on the geometry in a dedicated depth viewport scene.
It encodes camera-forward distance divided by `depth_range` in red, clamped to
`[0,1]`. Use a white clear/background color to represent no geometry at the depth
limit. Use an LDR depth viewport with linear tonemapping, no color adjustments
or glow, and default exposure; depth is numeric data rather than display color.
The supplied shader cancels the renderer's sRGB encoding for LDR readback.
Keep its camera pose/projection and geometry synchronized with the color
scene when combining the two. The sensor does not replace gameplay materials or
mirror scene geometry automatically. A custom depth-render pipeline can supply
the same normalized red-channel format. This makes the render setup explicit
using Godot viewports rather than Unreal SceneCapture's built-in capture modes.

Image sensors compose like any other sensor for training and ONNX inference.
`ScholaImageSensor` supplies shared image settings and layout helpers; use one of
the concrete camera classes rather than adding the base directly.

The [camera target example](../examples/camera_target/README.md) composes
`ScholaCameraSensor` with a rotation actuator and runs an exported policy.

## Observation adapters and tests

`agent.observation_adapters` processes the validated sensor dictionary. A
`ScholaStacker` with `output_kind=1` (Dict) retains history using keys such as
`00000000:rays_0` for the newest sample and `00000000:rays_1` for the preceding
sample. Episode resets clear history. `agent.get_effective_observation_space()` describes raw
sensor values; the interaction definition advertises the adapted space.

Build the runtime with `integration_tests=yes`, import the project, and run
`components_test.gd` and `components_parity_test.gd` using the Godot README commands.
Run actual color/depth GPU readback separately with a rendering display:

```sh
godot --rendering-method gl_compatibility --audio-driver Dummy --path Godot \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/integration/camera_render_test.gd
```

Run the same command with `--rendering-method mobile` for the Vulkan path.
The camera suite skips on a headless display. It verifies real color pixels,
selected channels, CHW ordering, rendered normalized depth, native dispatch and
viewport-size validation. Frozen milestone demos are not required or modified.

US11 adds two camera suites. `camera_sensor_test.gd` checks image spaces, channel
selection and configuration errors without rendering, so it runs headless.
`camera_capture_test.gd` checks rendered 8-bit normalization, non-square layout,
channel selection, repeated captures and frame timing; run it like the camera
suite above, with its path after `-a`.
