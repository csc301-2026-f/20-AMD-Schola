# Environment nesting

- **Status:** Accepted
- **Source:** [Oct. 23, 2026 partner meeting, US5](../../../deliverables/team/minutes/partner-meeting-05.md#us5-godot-scene-nodes)

## Decision

A `ScholaEnvironment` must not have another `ScholaEnvironment` ancestor, even
through ordinary grouping nodes. Multiple environments in one scene are supported
as independent, non-nested environments. Agents may be grouped beneath ordinary
nodes within one environment.

The recorded partner decision states that nested environments are unsupported.
Treating a nested scene hierarchy as independent training environments makes
agent ownership and reset effects ambiguous: a parent environment's gameplay
callbacks can mutate the child environment while its lifecycle is independent.
No hierarchical reinforcement-learning semantics are defined by Schola here.

## Enforcement

- Report an Inspector configuration warning on the nested environment.
- Reject training initialization or definition with a descriptive error.
- Reject reset/step operations if reparenting makes an environment nested during
  a training session, including reparenting from gameplay callbacks.
- Keep agent discovery bounded by environment nodes to avoid double-counting
  while diagnosing invalid scenes; this is not support for nesting.

Earlier implementation, README wording, and tests allowed nested environments.
They contradicted the recorded decision and must not be used to infer support.
Changing this policy requires an explicit replacement decision agreed with the
partner and affected story owners. Historical meeting minutes remain unchanged.
