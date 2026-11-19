# Manual environment debugging (US9)

Run a production Schola environment one action at a time, without a Python
trainer or network connection. This example uses the existing
`ScholaTrainingHost`, environment adapter, and episode lifecycle. It performs
no learning and does not use the test-only environment driver.

The five-position board and left/right actions illustrate one small discrete
environment; they are not a general environment viewer. For your own 2D or 3D
simulation, keep its normal Godot scene and supply actions matching its declared
spaces through the host API below. Adapt the example's controls to those actions.
`ScholaMonitor` can display episode telemetry independently of the simulation's
visuals; it does not render observations or generate actions.

## Run

Build the runtime extension using the [development guide](../../README.md).
Only the `schola` target is required; it includes `ScholaTrainingHost` and
does not link gRPC or Protocol Buffers. Its existing ONNX Runtime dependency
is still required, even though this example does not load a policy.

```sh
scons -C Godot schola platform=windows target=template_debug
godot --path Godot res://examples/manual_environment/main.tscn
```

Use your platform's build option on Linux or macOS. The repository's development
project also discovers the training add-on if installed; the manual workflow
never calls it. To run in a project without training dependencies, copy
`examples/manual_environment/` and `addons/schola/` into a fresh Godot project,
including the runtime extension and its platform libraries. Do not copy
`addons/schola_training/`. No Python process, training package, or server is
needed at runtime. Python/SCons may still be used to build the extension.

Click **Left** or **Right**, or use the arrow keys. Each action advances one
logical step, including when a button or toggle has keyboard focus. While
editing the seed, arrow keys move the text cursor instead; press Tab to leave
the field before using movement shortcuts. The five positions are numbered
0–4; position 4 is the goal.
Reaching it terminates the episode with reward +1. Other steps give -0.01.
Eight steps without reaching the goal truncate the episode. Final results
stay visible until **Reset** (or **R**); autoreset is disabled.

Enable **Random start** to choose position 0–3 using the seed field. Repeating
the same seed repeats the starting position. Fixed resets start at 0. The
display shows the complete structured result, including observations, reward,
termination, truncation, and info. The existing `ScholaMonitor` beside the
controls receives real host results: reset starts a display episode, each
successful action records its reward, and completion ends the display episode.
Its step count, return graph, and per-agent rewards reflect the actual lifecycle.
Failed actions and retained terminal results do not advance monitor telemetry.
Recoverable input errors leave the controls available. If an environment fault
closes the session, the monitor ends the episode, movement and Reset are disabled,
and the board instructs you to fix the error and restart the scene. The original
error remains visible, including after keyboard input.

## Use the host in your own scene

Put `ScholaEnvironment` nodes with configured agents in the active scene and
add a `ScholaTrainingHost`. Call it on the main thread after the scene becomes
`SceneTree.current_scene`. Environment IDs are assigned in scene-tree order;
agent IDs come from the definition, rather than node names.

```gdscript
var result := host.initialize_session()
if result["status"]["code"] != 0:
    push_error(result["status"]["message"])
    return
# Check every subsequent result in the same way before reading value.
result = host.set_autoreset_mode(2) # Disabled; set before define().
result = host.define()             # Inspect value.environments for IDs/spaces.
result = host.reset({0: {"seed": 42, "options": {"start": "random"}}})
var initial: Dictionary = result["value"][0]["walker"]
result = host.step({"actions": [{"walker": 1}]})
var state: Dictionary = result["value"]["state"][0]["walker"]
# state: observation, reward, terminated, truncated, info
result = host.close()
```

Reset settings are keyed by integer environment ID. Omit `seed` for an unseeded
reset; do not pass null. Seeds are signed 32-bit integers. Reset option keys
and values are strings interpreted by the environment. This example recognizes
`start = "random"`; other values use a fixed start. `reset({})` uses defaults.
Reset returns initial observations and info, without a step reward.

Step actions contain one dictionary per environment, in definition order,
mapping agent IDs to values matching their declared spaces. Here the action
is Discrete(2): 0 means left, 1 means right; observations are Discrete(5).
Every operation returns `{ "status": { "code": int, "message": String },
"value": ... }`. A nonzero status means failure and value is null. Never
interpret a failed result as an observation. Decode errors can be corrected
and retried; a lifecycle failure can close the session, requiring a new host.
Use `host.is_session_active()` on the main thread after a failed operation to
distinguish a usable session from one that has closed. The host also closes
when it leaves the scene tree.

## Verification

The focused GdUnit4 suite loads this exact scene and checks goal termination,
terminal-state preservation, explicit reset, truncation, seeded resets,
invalid-action errors without state advancement, monitor telemetry, and keyboard
movement with focused controls while preserving seed-field editing:

```sh
godot --headless --path Godot -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/integration/manual_environment_test.gd
```

See `training_host_test.gd` for broader multi-environment, seed validation,
autoreset, and session-failure coverage. No new connector or lifecycle API is
introduced by US9.
