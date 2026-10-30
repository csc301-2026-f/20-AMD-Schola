# Repository guidance

## Repository grounding

This repository contains the existing Unreal Engine implementation and the new Godot port. Establish which side of the repository a task belongs to before making changes.

- All Godot implementation, bindings, tests, demos, and Godot-specific documentation live under `Godot/`.
- Treat root implementation directories such as `Source/` and `Resources/` as part of the existing Unreal Schola codebase unless repository documentation explicitly identifies something as shared.
- For Godot work, use the Unreal implementation as design evidence and a source of shared Schola semantics. Do not modify Unreal files unless the task explicitly requires an Unreal or cross-engine change.
- Never add Godot-specific code to root Unreal directories.
- Shared capabilities should preserve Schola's cross-engine semantics while using Godot-native APIs and conventions.
- Before editing, classify the target as Godot, Unreal, shared infrastructure, course records, or a frozen artifact.
- If ownership is unclear, inspect neighboring files, repository documentation, and history before making changes.

## Repository workflow

Follow [CONTRIBUTING.md](CONTRIBUTING.md) for repository workflow and hygiene.

## Frozen deliverables

Past course deliverables are immutable historical artifacts.

- Inspect the repository tags to determine which deliverables have already been submitted.
- Never edit a submitted `deliverables/Dx/` directory unless the user explicitly asks to amend that deliverable.
- Demos associated with submitted deliverables are also frozen. For example, after D1 and D2 are tagged, `Godot/demo/d1/` and `Godot/demo/d2/` must not be modified.
- Do not update frozen deliverables or demos to reflect the current implementation, fix their wording, replace links, or keep them synchronized with living documentation.
- Store current plans, user stories, and implementation status in living documentation under `Godot/docs/`.
- New meeting records may be added under `deliverables/team/minutes/`. Do not rewrite existing minutes unless explicitly requested.
- If it is unclear whether an artifact is frozen, inspect the tags and repository history before editing.

An explicit user request overrides this rule only for the specifically named frozen files and scope.

## Godot work

- Read and follow the [Godot development contract](Godot/docs/development_contract.md) before changing files under `Godot/`.
- Use [Godot/README.md](Godot/README.md) for supported dependencies, build commands, and tests.
- Format changed Godot C++ with [Godot/.clang-format](Godot/.clang-format) and follow [Godot/.editorconfig](Godot/.editorconfig).
- Respect user-story ownership, module boundaries, and existing public contracts. Keep cross-story fixes focused and separate from feature work.
