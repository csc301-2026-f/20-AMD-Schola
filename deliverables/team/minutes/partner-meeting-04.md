# AMD Schola Partner Meeting 4

## Meeting details

- **Date:** Oct 16, 2026
- **Time:** 11:00 a.m.–12:00 p.m.
- **Location:** Microsoft Teams
- **Minutes prepared by:** Sanjay Ram / Shahyar Anfaz
- **Minutes source:** Shared Granola notes

## Attendees

### AMD

- Alexander Cann -- MTS @ AMD

### CSC301 team

- Guneev Pannu
- Sanjay Ram
- Bohdan Zmeul
- Vansh Sehrawat
- Shahyar Anfaz
- Isaac Tilahun
- Jimmy Zhu

## Documentation and repository updates

- A new AMD Schola repository commit changed state handling for multiple agents.
- The team could safely freeze its current upstream clone as the implementation baseline.
- Sphinx is the standard documentation system. reStructuredText is preferred but not required.
- Doxygen with Breathe provides an intermediate path for documenting C++, and the Godot C++ extension can follow the same approach.
- Any format compatible with Sphinx is acceptable. Agent-assisted documentation generation may also be considered.

## API design and architecture discussion

- Every API proposal had merged into `main`, allowing the team to begin implementation.
- Godot divides the responsibilities of Unreal's `UAbstractGymConnector` across four or five classes, including the environment lifecycle, coordinator, interfaces, and the engine-independent environment from US1.
- Most classes are engine-independent. Only US3 and US5 directly interface with Godot or Python.

### Scene structure

- A `ScholaEnvironment` node is the parent of one or more `ScholaAgent` nodes.
- An environment without agents reports an error because it represents an invalid configuration.
- The current agent nodes define the initial agent set. Dynamic spawning and despawning during an episode were not yet supported.

### Multi-agent lifecycle

- An agent that despawns should emit a terminal observation marked terminated or truncated so the training library stops requesting actions for it.
- The set of possible agents, including their names and observation and action spaces, must remain fixed across episodes.
- Adding entirely new agents during a training run is out of scope because machine-learning libraries do not support introducing new neural networks mid-training.
- The team should consult Ray and PettingZoo documentation for multi-agent termination semantics.

### Interface inheritance

- Multiple inheritance is acceptable for interfaces in the Godot implementation.
- Several constraints in the Unreal design resulted from Unreal's restriction against interface-to-interface inheritance and do not apply to Godot.

## Decisions

- Freeze the current AMD Schola clone as the upstream implementation baseline.
- Use Sphinx-compatible documentation, with reStructuredText preferred but not mandatory.
- Treat an environment without agents as an invalid configuration.
- Keep the set of possible agents fixed throughout a training run.
- Support interface multiple inheritance where it simplifies the Godot design.

## Action items

| Owner | Action                                                                                          | Status at meeting end |
|-------|-------------------------------------------------------------------------------------------------|-----------------------|
| Team  | Begin implementing the APIs merged into `main`.                                                 | Open                  |
| Team  | Prepare slides for Tuesday's TA Demo Day.                                                       | In progress           |
| Team  | Share updated slides at the next Friday partner meeting to demonstrate implementation progress. | Open                  |
| Team  | Update the Trello board before the next partner meeting.                                        | Open                  |
| Team  | Review Ray and PettingZoo documentation for multi-agent termination semantics.                  | Open                  |
