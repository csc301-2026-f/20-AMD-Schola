# US15 space-definition callback contract

## Implementation status

US15 implementation and local validation are complete through step 8. PR/team
review remains pending. The [story verification record](user_stories/US15.md#step-8-local-validation-and-review-nov-18-2026)
records build, formatting, integration-test, example, and scope checks, along with
their platform and interactive-editor limitations.

Steps 1-2 expose the optional `_define_spaces()` virtual hook, the metadata-only
`has_code_defined_spaces()` query on `ScholaAgent`, and the static `ScholaSpaces`
resource constructors.

Step 3 adds the resolver in `GodotAgentAdapter`. The first successful `define()`
calls the hook (or reads the Inspector when there is no hook), validates both
spaces, and saves a copy. Later `define()`, `observe()`, and `act()` calls use that
copy. Callers that reach `define()` directly, such as `ScholaOnnxPolicy` and the
stepper, already use code-defined spaces.

Step 4 connects startup:

- `ScholaAgent.get_configuration_errors()` skips the space checks when the script
  implements `_define_spaces()`, because the Inspector fields are unused. It still
  never runs the callback. `ScholaEnvironment.get_configuration_errors()` also
  accepts callback-only agents and retains authored-resource diagnostics for
  Inspector agents. Runtime startup uses separate scene-structure checks and
  validates spaces through `define()`, so mutable authored resources cannot
  invalidate an existing snapshot for either authoring path.
- `GodotEnvironmentAdapter::initialize()` then calls `define()` on each agent,
  which runs and checks the callback.
- `ScholaTrainingHost.initialize_session()` resolves every agent's spaces right
  after the configuration check. A broken callback therefore fails at session
  start with `INVALID_DATA`, naming the environment and the agent, just like a
  broken Inspector field. The agent keeps what it resolved, so the later `define()`
  from Python reuses it without running the callback again.

Editor warnings call the same configuration check, so they also stop reporting
empty Inspector space fields on callback agents. Step 5 adds Inspector help for
callback precedence, validation timing, and preservation of saved fields, plus
behavioral warning tests covering tool scripts and script/inheritance changes.

Step 6 adds scene save/load and lifecycle regression tests. These verify retained
snapshots across tree re-entry, resets, resource edits, policy reinitialization,
and later startup failures; new scene instances rebuild from saved configuration.
Nested observation/action validation, atomic failure, and corrected retries after
script errors are covered alongside the existing factory and startup tests.

Step 7 supplies a current, runnable [code-defined spaces example](../examples/code_defined_spaces/README.md).
It combines a large RGB Box with parameterized repeated nested observation and
action Dicts, uses the production training host locally, and supplies synthetic
sensor values separately from the space declarations. Build and run commands are
in the [Godot guide](../README.md#code-defined-spaces-example).

## Callback return value and precedence

A script attached to `ScholaAgent` may implement `_define_spaces()`. An inherited
implementation also counts as an override. The callback takes no arguments and
must return a non-null `ScholaSpaceDefinition` with these typed properties:

| Property | Required value |
| --- | --- |
| `observation` | A non-null `ScholaSpace` resource |
| `action` | A non-null `ScholaSpace` resource |

`ScholaSpaceDefinition` is a registered `RefCounted` class, not a plain C++
struct or a serialized Resource. Its static `create(observation, action)` factory
requires both arguments, each typed as `ScholaSpace`, and returns a new definition.
The writable properties retain references to their resources; they do not copy them.
Resources use existing space types,
validation, bounds broadcasting, nested Dict ordering, and serialization semantics.

For example:

```gdscript
extends ScholaAgent

func _define_spaces() -> ScholaSpaceDefinition:
    return ScholaSpaceDefinition.create(
        ScholaSpaces.box([1, 30, 32], 0.0, 1.0),
        ScholaSpaces.discrete(5)
    )
```

The native virtual hook also declares `ScholaSpaceDefinition` as its return type.
Godot exposes the factory argument types, property types, and callback return type
to GDScript tooling, allowing incompatible return declarations, missing factory
arguments, and statically known wrong argument types to be caught before startup.
Dynamic values can still require runtime type checks. Null definitions, null fields,
and invalid resource definitions remain runtime errors. The resolver validates both
resources before saving either space. Errors start with `Agent '<id>':` and name
the property, for example `_define_spaces().action is null`.

This replaces the previous Dictionary callback contract; there is no Dictionary
fallback. To migrate, change the return annotation and replace the outer
`{"observation": obs, "action": act}` with `ScholaSpaceDefinition.create(obs, act)`.
Nested `ScholaSpaces.dict(...)` definitions and observation/action values keep
their existing representations. Rebuild the runtime extension before loading
scripts that use the new class.

`ScholaSpaceDefinition.new()` is also available for explicit property assignment.
Its fields start null, so both must be assigned before initialization. The factory
does not validate bounds or reject null arguments; initialization supplies the
agent-specific diagnostics. After successful resolution, edits to either property
or its referenced resources do not change the agent's saved core snapshot.

When the hook is absent, Inspector assignments supply both spaces. When present,
the hook supplies both spaces and takes precedence over both assignments. An
invalid result is an error; it never falls back to Inspector values or mixes
sources. Inspector properties and their getters continue to expose the authored
assignments. Resolution must not overwrite them or change saved scenes.

## Space constructors

`ScholaSpaces` is a static utility class; call its methods directly without creating
an instance. Every call returns a new resource of the existing concrete type.

| Method | Return type | Arguments |
| --- | --- | --- |
| `box(shape, low, high, dtype = FLOAT32)` | `ScholaBoxSpace` | `PackedInt32Array` shape, two scalar numeric bounds, integer dtype |
| `box_bounds(shape, low = [], high = [], dtype = FLOAT32)` | `ScholaBoxSpace` | `PackedInt32Array` shape, two `PackedFloat32Array` bounds, integer dtype |
| `discrete(n)` | `ScholaDiscreteSpace` | Integer choice count |
| `multi_discrete(nvec)` | `ScholaMultiDiscreteSpace` | `PackedInt32Array` choice counts |
| `multi_binary(n)` | `ScholaMultiBinarySpace` | Integer binary element count |
| `dict(spaces)` | `ScholaDictSpace` | Dictionary mapping String keys to space resources |

Godot converts compatible plain array literals to the packed argument types.
`box()` stores one bound per side; existing Box conversion broadcasts those bounds
across the explicit shape. `box_bounds()` supports empty bounds (unbounded for
floating dtypes), singleton broadcasting, and row-major per-element arrays. It also
preserves existing shape inference when the supplied shape is empty.

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

Named dtype constants use the existing core/Inspector values: `FLOAT32`, `UINT8`,
`UINT16`, `UINT32`, `UINT64`, `INT8`, `INT16`, `INT32`, `INT64`, `FLOAT16`, `FLOAT64`,
and `BOOL`. Dtype selects the space's declared type; bounds retain the existing
float32 storage and representability limits.

Constructors assign resource properties and do not clamp, normalize, or throw for
invalid definitions. Call `get_definition_error()` on the result to validate it,
just as with an Inspector-authored resource. Invalid sizes, shapes, bounds, dtype
values, and Dict entries remain available for correction and produce existing
resource diagnostics. Godot's ordinary typed-call checks apply to arguments of
the wrong type. Dict constructors preserve the existing sharing of child resources
and Dictionary assignments; they do not deep-copy their children.

These resources use standard Godot saving/loading. No generated-resource authoring
workflow or custom serialization format is introduced.

## Initialization and snapshot lifetime

Steps 3 and 4 implement these rules:

1. Training and standalone inference resolve spaces on the main thread before
   runtime configuration checks and agent-definition consumption.
2. The first successful resolution captures validated core-space values. Repeated
   `define()` calls and other consumers reuse those values rather than rerunning
   the callback or reconverting mutable resources.
3. Episode resets, policy-memory resets, tree exit/re-entry, and changes to resource
   properties or configuration do not invalidate a successful snapshot. Actual
   observations must continue to match it.
4. Rebuilding requires stopping affected consumers and recreating the configured
   scene with new agent/environment instances, then initializing again. Policy
   compatibility must be checked against the new definition. Reinitializing a
   policy alone does not clear the agent snapshot. Live reconfiguration is outside
   US15's scope.
5. Failed resolution publishes no snapshot and can be retried after correction.
   If resolution succeeds but a later initialization stage fails, the snapshot is
   retained. Applying changed configuration then requires scene recreation.

These rules apply to Inspector-authored and callback-authored spaces. Before step 3,
the adapter re-read the Inspector on every `define()` call. It now keeps the first
successful result.

After a successful resolution, invalidating or clearing an authored Inspector
resource still produces editor diagnostics, but does not block runtime startup,
definition, or value validation using the saved snapshot. With no snapshot yet,
invalid Inspector definitions fail through the same resolver as usual.

A `define()` call made while `_define_spaces()` is still running fails instead of
recursing.

Callbacks must construct definitions deterministically from configuration available
before session initialization. Do not depend on episode state, `_ready()` ordering,
or gameplay side effects. Loops and helper functions are permitted.

## Editor and tooling boundary

`has_code_defined_spaces()` inspects script metadata, including base scripts, and
does not execute the hook. Ordinary Inspector warning queries must also remain
metadata-only, including for tool scripts. Since step 4, the configuration check
behind those warnings uses this query to skip the space checks for callback agents,
so unused Inspector fields are not reported as missing spaces.

Inspector help on both space properties explains callback precedence, runtime
validation, and why saved fields can remain empty. When a direct or inherited
`_define_spaces()` callback is detected, a "Spaces defined in code" notice appears
at the top of the Inspector. Detection uses script metadata without running the
callback. Missing `_observe()` and
`_act()` hooks still produce warnings independently of space authorship. Attaching
or detaching scripts and changes to scripts in the inheritance chain refresh the
warning state; these checks do not evaluate the callback, including `@tool` hooks.

Discovering the actual callback result requires evaluating it on a configured
instance. Results do not automatically appear in Inspector fields. Editor preview,
generated resource files, type generation, new space types, and camera capture are
outside this story's scope.
