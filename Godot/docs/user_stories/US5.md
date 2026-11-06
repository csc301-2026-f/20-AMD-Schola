# US5: Configure Schola through Godot-native tools

- **Owner:** Vansh
- **Status:** Core bindings implemented
- **Last updated:** Nov. 5, 2026

## Story

As a Godot developer, I want to configure agents and environments through nodes and the Inspector so that I can use familiar Godot workflows instead of editing protocol or networking code.

## Acceptance criteria

- A developer can add the required Schola components to a scene using Godot's normal node workflow.
- Essential settings are visible and editable in the Inspector with understandable names and defaults.
- Agent identities and observation/action resources can be configured without modifying Schola's internal source code.
- Episode truncation can be implemented through the environment hooks without a special-purpose `MaxEpisodeSteps` node.
- Running the scene reports missing or conflicting configuration clearly.

## Progress

- Native `ScholaEnvironment` and `ScholaAgent` nodes are registered. Agents expose identity fields and observation/action references to US2 space resources in the Inspector.
- Empty agent IDs resolve to the node name; empty agent types resolve to the effective agent ID. Configured values remain unchanged when resolving defaults, saving scenes, or duplicating nodes. The integrated US1 adapters use the resolved values.
- `_get_step_result(agent)` replaces `_get_reward`, `_is_terminated`, `_is_truncated`, and `_get_info`. It returns a required finite numeric reward, optional boolean completion flags, and optional string-to-string info. Invalid results produce agent-specific errors without publishing partial result batches. `_reset_episode(seed, options)` remains separate and optional. See the [callback contract](../../README.md#episode-endings).
- Built-in episode step limits have been removed from the node API and lifecycle. Users implement their own cutoff by returning `truncated: true`; no special-purpose `MaxEpisodeSteps` node is required.
- Inspector help explains identities, space settings, defaults, and resource sharing. Positive-size fields have range hints. The Schola editor dock scrolls within the available space instead of displacing the editor's bottom panels.
- Editor warnings report missing or invalid spaces, missing agents, duplicate resolved IDs with both conflicting node paths, and missing required behavior hooks. Warnings refresh after resource edits, nested-resource edits, script changes, agent addition/removal, renaming, and reparenting. Hook checks recognize inherited methods without executing gameplay scripts in the editor.

## Verification

- Before the latest merge from `main`, the Windows native build and all 40 existing Godot integration tests passed, including identity/scene round trips and the consolidated callback path.
- An editor smoke check verified warning refreshes for scene-tree edits and script attachment. A separate layout check verified that enabling the Schola dock keeps the bottom panel within the editor window.
- Vansh completed the manual editor persistence checks. This records owner-reported manual verification separately from the automated checks.
- The scratch scene successfully initializes and resets, applies three actions, and returns a user-defined truncation on the third step. It uses the optional `ScholaEnvironmentTestDriver`, which is available only in builds with `integration_tests=yes`.

## Scope

- A runnable gameplay example and movement-specific reward behavior are outside US5's acceptance criteria. `examples/basic_environment/` remains a registration probe.
- `ScholaTrainingHost` is included from `main`. Its integration-test environment uses `_get_step_result` for reward, completion, and info; the production US4 implementation is unchanged.
- CI builds the native adapter test driver with `integration_tests=yes`, so the consolidated callback suite runs alongside the other integration tests.

Frozen D1/D2 demos and the archived D1 prototype are historical artifacts, not evidence of current plugin functionality.
