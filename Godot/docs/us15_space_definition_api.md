# US15 space-definition callback contract

## Implementation status

The implementation is merged on main: PR #58 introduced code-defined spaces and PR #93 replaced the combined callback with independent observation and action hooks. The [story](user_stories/US15.md) records acceptance criteria and current checks; the [verification record](verification.md) records the current revision and suite results.

The agent exposes the optional `_define_observation_space()` and `_define_action_space()` virtual hooks, the metadata-only `has_code_defined_spaces()` query on `ScholaAgent`, and the static `ScholaSpaces` resource constructors.

Space resolution lives in `GodotAgentAdapter`. The first successful `define()` calls the hook (or reads the Inspector when there is no hook), validates both spaces, and saves a copy. Later `define()`, `observe()`, and `act()` calls use that copy. Callers that reach `define()` directly, such as `ScholaOnnxPolicy` and the stepper, already use code-defined spaces.

Startup uses the same resolution path:

- `ScholaAgent.get_configuration_errors()` skips each space check when the script implements the corresponding space hook, because that Inspector field is unused. It never runs the callbacks. `ScholaEnvironment.get_configuration_errors()` also accepts callback-only agents and retains authored-resource diagnostics for Inspector agents. Runtime startup uses separate scene-structure checks and validates spaces through `define()`, so mutable authored resources cannot invalidate an existing snapshot for either authoring path.
- `GodotEnvironmentAdapter::initialize()` then calls `define()` on each agent, which runs and checks the callback.
- `ScholaTrainingHost.initialize_session()` resolves every agent's spaces right after the configuration check. A broken callback therefore fails at session start with `INVALID_DATA`, naming the environment and the agent, just like a broken Inspector field. The agent keeps what it resolved, so the later `define()` from Python reuses it without running the callback again.

Editor warnings call the same configuration check, so they do not report unused empty Inspector space fields on callback agents. Inspector help explains callback precedence, validation timing, and preservation of saved fields. Behavioral warning tests cover tool scripts and script/inheritance changes.

Scene save/load and lifecycle regression tests exercise the snapshot contract. These verify retained snapshots across tree re-entry, resets, resource edits, policy reinitialization, and later startup failures; new scene instances rebuild from saved configuration. Nested observation/action validation, atomic failure, and corrected retries after script errors are covered alongside the existing factory and startup tests.

The current [code-defined spaces example](../examples/code_defined_spaces/README.md) combines a large RGB Box with parameterized repeated nested observation and action Dicts, uses the production training host locally, and supplies synthetic sensor values separately from the space declarations. Build and run commands are in the [Godot guide](../README.md#code-defined-spaces-example).

## Callback return value and precedence

A script attached to `ScholaAgent` may implement either or both optional hooks. Inherited implementations count as overrides. Each hook takes no arguments and returns a non-null `ScholaSpace` resource:

```gdscript
extends ScholaAgent

func _define_observation_space() -> ScholaSpace:
    return ScholaSpaces.box([1, 30, 32], 0.0, 1.0)

func _define_action_space() -> ScholaSpace:
    return ScholaSpaces.discrete(5)
```

Each hook overrides only its corresponding Inspector or component-composed space. An absent hook uses the existing authored configuration for that side. A present hook returning null or an invalid resource fails without falling back. Both spaces are validated before either snapshot is saved; failures allow a corrected retry. Errors name the agent and hook, for example `Agent 'robot': _define_action_space() returned null; return a ScholaSpace`.

The native virtuals expose `ScholaSpace` return types to GDScript tooling. Incompatible return declarations are rejected before startup. Resources keep their existing validation, sharing, serialization, and nested Dict ordering semantics. Inspector properties continue to expose authored assignments and are never overwritten with callback results.

This replaces `_define_spaces()` and removes `ScholaSpaceDefinition`. To migrate, move the former observation expression into `_define_observation_space()` and the action expression into `_define_action_space()`, returning each resource directly. Rebuild the runtime extension before loading migrated scripts. Nested Dict spaces, observation/action values, and wire formats retain their existing representations.

## Space constructors

`ScholaSpaces` is a static utility class; call its methods directly without creating an instance. Every call returns a new resource of the existing concrete type.

| Method | Return type | Arguments |
| --- | --- | --- |
| `box(shape, low, high, dtype = FLOAT32)` | `ScholaBoxSpace` | `PackedInt32Array` shape, two scalar numeric bounds, integer dtype |
| `box_bounds(shape, low = [], high = [], dtype = FLOAT32)` | `ScholaBoxSpace` | `PackedInt32Array` shape, two `PackedFloat32Array` bounds, integer dtype |
| `discrete(n)` | `ScholaDiscreteSpace` | Integer choice count |
| `multi_discrete(nvec)` | `ScholaMultiDiscreteSpace` | `PackedInt32Array` choice counts |
| `multi_binary(n)` | `ScholaMultiBinarySpace` | Integer binary element count |
| `dict(spaces)` | `ScholaDictSpace` | Dictionary mapping String keys to space resources |

Godot converts compatible plain array literals to the packed argument types. `box()` stores one bound per side; existing Box conversion broadcasts those bounds across the explicit shape. `box_bounds()` supports empty bounds (unbounded for floating dtypes), singleton broadcasting, and row-major per-element arrays. It also preserves existing shape inference when the supplied shape is empty.

```gdscript
var image := ScholaSpaces.box([3, 30, 32], 0, 255, ScholaSpaces.UINT8)
var position := ScholaSpaces.box_bounds([3], [-10, -5, 0], [10, 5, 100])
var velocity := ScholaSpaces.box_bounds([3]) # Unbounded float32.
var limbs := {}
for limb in ["left", "right"]:
    limbs[limb] = ScholaSpaces.dict({
        "position": ScholaSpaces.box([3], -1, 1),
        "contact": ScholaSpaces.discrete(2),
    })
var observation := ScholaSpaces.dict({
    "image": image,
    "limbs": ScholaSpaces.dict(limbs),
})
```

Named dtype constants use the existing core/Inspector values: `FLOAT32`, `UINT8`, `UINT16`, `UINT32`, `UINT64`, `INT8`, `INT16`, `INT32`, `INT64`, `FLOAT16`, `FLOAT64`, and `BOOL`. Dtype selects the space's declared type; bounds retain the existing float32 storage and representability limits.

Constructors assign resource properties and do not clamp, normalize, or throw for invalid definitions. Call `get_definition_error()` on the result to validate it, just as with an Inspector-authored resource. Invalid sizes, shapes, bounds, dtype values, and Dict entries remain available for correction and produce existing resource diagnostics. Godot's ordinary typed-call checks apply to arguments of the wrong type. Dict constructors preserve the existing sharing of child resources and Dictionary assignments; they do not deep-copy their children.

These resources use standard Godot saving/loading. No generated-resource authoring workflow or custom serialization format is introduced.

## Initialization and snapshot lifetime

Observation adapters apply after either authoring path resolves its raw spaces. The saved definition includes the adapted observation space, while `_observe()` continues to return values in the raw space. Repeated `define()` calls on script agents reuse the adapter instances and their history; episode resets clear history without rebuilding definitions. Training startup resolves `get_possible_agents()`, including detached prototypes declared by dynamic environments; live instances resolve their own definitions when they join and must match the prototype.

On a side without a callback, US8 sensors and actuators may supply composed spaces instead of explicit Inspector assignments. Their live component layout checks remain in effect. Component-authored sides retain US8's explicit redefinition behavior when a new environment initializes the same agent; uncomposed Inspector sides retain their saved values. For a callback agent using component dispatch, each declared space must match the corresponding composition unless `_observe()` or `_act()` overrides that side. Mismatches fail at definition time rather than indexing an incompatible space during a step. Effective-space getters remain metadata/configuration queries and never execute the callback.

Initialization follows these rules:

1. Training and standalone inference resolve spaces on the main thread before runtime configuration checks and agent-definition consumption.
2. The first successful resolution captures validated core-space values. Repeated `define()` calls and other consumers reuse those values rather than rerunning the callback or reconverting mutable resources.
3. Episode resets, policy-memory resets, tree exit/re-entry, and changes to resource properties or configuration do not invalidate a successful snapshot. Actual observations must continue to match it.
4. Rebuilding requires stopping affected consumers and recreating the configured scene with new agent/environment instances, then initializing again. Policy compatibility must be checked against the new definition. Reinitializing a policy alone does not clear the agent snapshot. Live reconfiguration is outside US15's scope.
5. Failed resolution publishes no snapshot and can be retried after correction. If resolution succeeds but a later initialization stage fails, the snapshot is retained. Applying changed configuration then requires scene recreation.

These rules apply to Inspector-authored and callback-authored spaces. The adapter keeps the first successful definition.

After a successful resolution, invalidating or clearing an authored Inspector resource still produces editor diagnostics, but does not block runtime startup, definition, or value validation using the saved snapshot. With no snapshot yet, invalid Inspector definitions fail through the same resolver as usual.

A `define()` call made while either space hook is still running fails instead of recursing.

Callbacks must construct definitions deterministically from configuration available before session initialization. Do not depend on episode state, `_ready()` ordering, or gameplay side effects. Loops and helper functions are permitted.

## Editor and tooling boundary

`has_code_defined_spaces()` inspects script metadata, including base scripts, and returns true when either hook exists. The side-specific queries `has_code_defined_observation_space()` and `has_code_defined_action_space()` identify which side is overridden. None executes the hooks. Ordinary Inspector warning queries must also remain metadata-only, including for tool scripts. The configuration check behind those warnings uses this query to skip only the checks for code-defined sides, so unused Inspector fields are not reported as missing spaces.

Inspector help on both space properties explains callback precedence, runtime validation, and why saved fields can remain empty. When a direct or inherited space hook is detected, a "Spaces defined in code" notice appears at the top of the Inspector. Detection uses script metadata without running the callback. Missing `_observe()` and `_act()` hooks still produce warnings independently of space authorship. Attaching or detaching scripts and changes to scripts in the inheritance chain refresh the warning state; these checks do not evaluate the callback, including `@tool` hooks.

Discovering the actual callback result requires evaluating it on a configured instance. Results do not automatically appear in Inspector fields. Editor preview, generated resource files, type generation, new space types, and camera capture are outside this story's scope.
