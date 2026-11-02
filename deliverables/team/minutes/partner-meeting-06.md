# AMD Schola Partner Meeting 6

## Meeting details

- **Date:** Oct. 30, 2026
- **Time:** 11:00–11:30 a.m.
- **Location:** Microsoft Teams
- **Minutes source:** Meeting transcript

## Attendees

### AMD

- Alexander Cann -- MTS @ AMD

### CSC301 team

- Guneev Pannu
- Bohdan Zmeul
- Vansh Sehrawat
- Shahyar Anfaz
- Isaac Tilahun
- Jimmy Zhu

### Absent

- Sanjay Ram

## Progress review

### US1: Godot agent and environment adapters

- The adapters API and bind hooks are complete, allowing Godot developers to override `observe`, `act`, and `define`.
- The agent adapter is complete, including conversions between Godot `Variant` values and core points and spaces.
- The environment adapter header is written, but its implementation remains.
- After the environment adapter is complete, US1 needs end-to-end scene testing and cleanup.

### US2: Spaces and points

- The team compared the existing union-type implementation with the templated alternative discussed the previous week.
- The existing union-type approach was confirmed because it is cleaner and avoids additional complexity.

### US4: Episode lifecycle

- `ScholaTrainingHost` is complete. It discovers environments in deterministic scene-tree order, creates one lifecycle per environment, and keeps environment IDs fixed for the session.
- Initialization and operation outputs are transactional, so failures do not expose partial sessions, definitions, states, or step results.
- Godot-facing operations enforce main-thread execution.
- A missing environment node or any coordinator or environment failure closes the whole session while preserving the original error.
- `_exit_tree` performs clean shutdown.
- End-to-end testing is blocked until the US1 environment adapter is available.

### US5: Godot-native scene nodes

- The last four step callbacks are being combined into `get_step_result`; `reset_episode` remains separate because it has different behavior and return data.
- The proposed optional `MaxEpisodeSteps` node was judged too special-purpose and not extensible.
- Two acceptable directions were discussed: let users implement truncation through existing hooks, or later introduce a generic environment-modifier interface similar to a Gymnasium wrapper.
- The team leaned toward removing the special-purpose node. Vansh will update US5 accordingly.

## Error-handling proposal

- The core continues to return `Status` values and remains independent of Godot.
- `status.h` is the sole translation point from core statuses to Godot errors.
- Failing Godot methods return a Godot error code; value-returning methods return `null` on failure where appropriate.
- A shared helper reports the class, method, and reason, and `get_last_error` is cleared at the beginning of each call.
- Self-running nodes also emit failure signals, scene-setup mistakes produce editor warnings, and failures do not throw or crash.
- Alex asked the team to share the slides so he could review the proposal and follow up with questions.

## Decisions

- Retain the US2 union-type implementation.
- Remove maximum-episode-step handling from US4.
- Remove the special-purpose `MaxEpisodeSteps` node proposed for US5.
- Keep `reset_episode` separate and combine the four step-result callbacks into `get_step_result`.

## Action items

| Owner | Action | Status at meeting end |
|---|---|---|
| Isaac | Complete the US1 environment adapter, then run end-to-end tests and cleanup. | Open |
| Vansh | Remove the proposed `MaxEpisodeSteps` node and continue the US5 callback consolidation. | Open |
| Bohdan | Post the recurrent-model maximum-sequence-length question in the group chat. | Open |
| Team | Share the sprint slides in the group chat for Alex. | Open |
