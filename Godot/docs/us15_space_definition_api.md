# US15 space-definition callback contract

## Implementation status

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
  never runs the callback. So `ScholaEnvironment.get_configuration_errors()`, which
  both the environment adapter and the training host check first, accepts
  callback-only agents.
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

## Callback return value and precedence

A script attached to `ScholaAgent` may implement `_define_spaces()`. An inherited
implementation also counts as an override. The callback takes no arguments and
must return a Dictionary with these required String keys:

| Key | Required value |
| --- | --- |
| `observation` | A non-null `ScholaSpace` resource |
| `action` | A non-null `ScholaSpace` resource |

Any other key is rejected and named in the error, so a misspelling such as
`observations` is reported as itself. Resources use existing space types,
validation, bounds broadcasting, nested Dict ordering, and serialization semantics.

For example:

```gdscript
extends ScholaAgent

func _define_spaces() -> Dictionary:
    return {
        "observation": ScholaSpaces.box([1, 30, 32], 0.0, 1.0),
        "action": ScholaSpaces.discrete(5),
    }
```

The native hook returns `Variant` so malformed results can reach the resolver and
receive an agent-specific diagnostic. A Dictionary return annotation is recommended
in user scripts. The resolver checks the return type, keys, resource types,
and both resource definitions before saving either space. Errors start with
`Agent '<id>':` and name the entry, for example `_define_spaces()["action"] is null`.

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
validation, and why saved fields can remain empty. Missing `_observe()` and
`_act()` hooks still produce warnings independently of space authorship. Attaching
or detaching scripts and changes to scripts in the inheritance chain refresh the
warning state; these checks do not evaluate the callback, including `@tool` hooks.

Discovering the actual callback result requires evaluating it on a configured
instance. Results do not automatically appear in Inspector fields. Editor preview,
generated resource files, type generation, new space types, and camera capture are
outside this story's scope.
