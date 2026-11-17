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

Still pending: the configuration checks in `GodotEnvironmentAdapter::initialize()`
and `ScholaTrainingHost` run before `define()` and still reject empty Inspector
fields (step 4), and editor warnings still report them (step 5).

## Callback return value and precedence

A script attached to `ScholaAgent` may implement `_define_spaces()`. An inherited
implementation also counts as an override. The callback takes no arguments and
must return a Dictionary with these required String keys:

| Key | Required value |
| --- | --- |
| `observation` | A non-null `ScholaSpace` resource |
| `action` | A non-null `ScholaSpace` resource |

Additional entries are reserved and must be rejected by the future resolver to
catch misspelled or unsupported fields. Resources use existing space types,
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
in user scripts. The resolver will check the return type, keys, resource types,
and both resource definitions before publishing either space.

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

The following is the contract for the remaining implementation steps:

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
metadata-only, including for tool scripts. Later warning integration will recognize
callback configuration without treating unused Inspector fields as missing spaces.

Discovering the actual callback result requires evaluating it on a configured
instance. Results do not automatically appear in Inspector fields. Editor preview,
generated resource files, type generation, new space types, and camera capture are
outside this story's scope.
