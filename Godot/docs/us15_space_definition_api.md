# US15 space-definition callback contract

## Implementation status

Step 1 exposes the optional `_define_spaces()` virtual hook and the metadata-only
`has_code_defined_spaces()` query on `ScholaAgent`. Runtime invocation, validation,
snapshot caching, startup integration, factory helpers, and updated warning behavior
are subsequent steps. Defining this callback alone does not configure runtime
spaces yet; initialization still reads Inspector assignments.

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

For example, this uses existing constructors rather than the planned factories:

```gdscript
extends ScholaAgent

func _define_spaces() -> Dictionary:
    var observation := ScholaBoxSpace.new()
    observation.shape = PackedInt32Array([1, 30, 32])
    observation.low = PackedFloat32Array([0.0])
    observation.high = PackedFloat32Array([1.0])

    var action := ScholaDiscreteSpace.new()
    action.n = 5
    return {"observation": observation, "action": action}
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

These rules apply to Inspector-authored and callback-authored spaces. They change
the current adapter behavior, which refreshes cached spaces on every successful
`define()` call; that behavior has not changed in step 1.

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
