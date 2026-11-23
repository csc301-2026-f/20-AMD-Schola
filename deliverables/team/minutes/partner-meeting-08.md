# AMD Schola Partner Meeting 8

## Meeting details

- **Date:** Nov. 13, 2026
- **Time:** 11:00 a.m.–[confirm end time]
- **Location:** Microsoft Teams
- **Minutes prepared by:** Sanjay Ram
- **Minutes source:** Granola notes and meeting transcript

## Attendees

### AMD

- Alexander Cann -- MTS @ AMD

### CSC301 team

- [confirm attendees]

## Racing game demo progress

- The car and racetrack scene is built. Training is not complete yet.
- The target is to finish it for the next meeting. It will serve as both the US13 production example and the Deliverable 4 submission.
- Deliverable 4 is due in two weeks. After it is submitted, code is frozen, and only documentation and CI changes follow.

## Demo design feedback

- Alex recommended starting with a simple forward/backward reward test before the full racetrack.
  - Bugs are easier to isolate when the environment's dynamics are trivial.
  - The racetrack has too many possible failure points to debug cleanly from the start.
- Once the system is verified end to end, the racetrack makes a strong showpiece.
- Alex suggested adding an input display to the demo, such as a WASD overlay or a steering-wheel and pedal visual.
  - Without it, the audience sees a video game rather than an RL agent or a framework.
  - It puts the team's contribution in context: the scaffolding that makes the result easy to replicate.
  - It is mainly for the graded presentation and is not a hard requirement.
- The trained model should be committed to the repository through Git LFS, in a dedicated example folder.
  - The folder will be restructured when the work is integrated into the main repository alongside all three plugins.

## Dynamic training populations and respawn semantics

- The current approach uses a fixed pool of predefined agent IDs per episode, mirroring Unreal's model.
  - The maximum number of agents in a scene is capped but arbitrary, and is set when training starts.
  - Godot has no native way to pause a node, so this constraint is built into the design.
- Respawn semantics are unclear. RLlib and PettingZoo handle respawning differently, and Schola's integration with them is not fully documented.
- The best starting point is to replicate Unreal's behavior directly.
- Once caught up, Alex will run edge-case tests and send a concrete specification of the expected scenarios.

## Decisions

- Verify the system end to end with a simple forward/backward reward test before training on the racetrack.
- Commit the trained racing model through Git LFS in a dedicated example folder.
- Replicate Unreal's respawn behavior for dynamic training populations until Alex's specification arrives.

## Action items

| Owner | Action | Status at meeting end |
|---|---|---|
| Team | Verify the system end to end with a simple forward/backward reward test. | Open |
| Team | Add an input display to the racing demo showing the agent's actions. | Open |
| Team | Ask the course instructor whether Alex may do a GitHub code review before D4, given the rules for external partners. | Open |
| Alex | Run respawn edge-case tests and send a specification of the expected scenarios. | Open |
