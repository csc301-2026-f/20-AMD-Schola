# US5: Configure Schola through Godot-native tools

- **Owner:** Vansh
- **Status:** In progress
- **Last updated:** Oct. 30, 2026

## Story

As a Godot developer, I want to configure agents and environments through nodes and the Inspector so that I can use familiar Godot workflows instead of editing protocol or networking code.

## Acceptance criteria

- A developer can add the required Schola components to a scene using Godot's normal node workflow.
- Essential settings are visible and editable in the Inspector with understandable names and defaults.
- The demonstration project can be configured without modifying Schola's internal source code.
- The demonstration agent receives a small reward for moving backward, a larger reward for moving forward, and a penalty for remaining still.
- Episode truncation can be implemented through the environment hooks without a special-purpose `MaxEpisodeSteps` node.
- Running the scene reports missing or conflicting configuration clearly.

## Progress

- Native `ScholaEnvironment` and `ScholaAgent` nodes and their Inspector configuration are implemented.
- The last four step-result callbacks are being combined into `get_step_result`; `reset_episode` remains separate.
- The proposed special-purpose `MaxEpisodeSteps` child node will be removed. Users can implement truncation through existing hooks; a generic environment-modifier interface may be considered later if needed.
- The callback consolidation and related implementation work remain in progress.
