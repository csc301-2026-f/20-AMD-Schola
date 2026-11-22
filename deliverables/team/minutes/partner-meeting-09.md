# AMD Schola Partner Meeting 9

## Meeting details

- **Date:** Nov. 20, 2026
- **Time:** 11:00 a.m.–[confirm end time]
- **Location:** Microsoft Teams
- **Minutes prepared by:** Sanjay Ram
- **Minutes source:** Granola notes and meeting transcript

## Attendees

### AMD

- Alexander Cann -- MTS @ AMD

### CSC301 team

- [confirm attendees]

## User story progress

### US13: Training node

- Complete and merged.
- The Godot training node connects to Python and collects each agent's observation and action spaces when training starts.

### US15: Code-defined action and observation spaces

- Complete.
- A `define_spaces` callback lets developers set spaces in GDScript instead of the Inspector.
- When both are present, the code takes priority over the Inspector settings. The spaces are cached for the whole training session.
- Feedback: the callback should return a struct, not a Dictionary with mandatory keys, which is an anti-pattern.

### US12: Multi-agent training

- Complete.
- Most of the multi-agent logic already existed. The work focused on tests and a two-agent example scene.
- Fixed connector reconnection: a session now stops cleanly while the connector keeps listening for Python's next session.
- The two-agent scene uses a 1D number line with both shared and individual rewards.

### US14: Sequence length export

- Complete.
- The sequence length is written to the model's metadata on export. It can be overridden on import, where 0 means use the model's value.

### US8: Reusable sensors and actuators

- Complete.
- Pre-built sensors and actuators mean developers do not need to learn Schola's nodes from scratch.
- Generic Schola sensor and actuator base classes are available for custom subclasses.

### US9: GDScript training checker

- Complete.
- A lightweight GDScript wrapper, about 300 lines, checks the environment setup before a full training run.
- 9 example tests and 14 host tests pass headlessly on Windows.

### US10: Circular buffer and observation stacking

- Complete.
- A generic observation adapter pipeline with Box stacking, Dict stacking, and an abstract stacker base.
- Each agent owns its own adapter instances, so one agent cannot affect another agent's history.
- 150+ passing tests cover layouts, stacking axes, bounds, key ordering, and default padding.

### US11: Camera sensor

- In progress.
- Frames go stale during training because rendering cannot keep up with training speed.
- The tradeoff is to accept stale frames or slow training down to sync with the render thread. Unreal Schola has the same issue.

## Demo

- The team showed a trained car model running inference on the track.
  - Reward: distance along the track, plus a bonus for staying centered.
  - Goal: drive as far as possible without hitting the walls or getting stuck.
  - Input smoothing is applied: the model outputs values from -1 to 1, which are not applied to the car immediately.
- The team plans to add obstacles to make the demo more impressive for the final presentation.

## Feedback and timeline

- The remaining work is estimated at 6 days, and up to 8 days. [confirm what "Codex estimate" refers to]
- Code freezes on Tuesday, Nov. 24, the presentation day. Only documentation changes follow.
- Alex said the testing slides need more detail on what is and is not covered.
  - 150 tests over a small surface do not show full coverage without context.
  - He wants to understand how edge cases are handled and which workflows are verified.
- Next meeting: Tuesday, 11:30 a.m.–12:30 p.m. [confirm date: the notes say "Tuesday 20th November", but Nov. 20 was this meeting, a Friday]
  - Alex will review the repository's architecture beforehand and bring specific feedback.
  - The meeting may be cancelled if the issues are minor. Alex will confirm on Monday.

## Decisions

- Code freezes on presentation day. After that, only documentation changes are made.
- The testing slides will explain coverage, edge cases, and verified workflows, not only test counts.

## Action items

| Owner | Action | Status at meeting end |
|---|---|---|
| Team | Share the slide deck in the chat, with duplicate slides removed. | Open |
| Team | Add testing detail to the slides: what is covered, which edge cases are handled, and which workflows are verified. | Open |
| Team | Send Alex the repository link so he can review the architecture before Tuesday. | Open |
| Alex | Review the repository architecture and confirm on Monday whether Tuesday's meeting is needed. | Open |
