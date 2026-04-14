# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Finalmente meu Jogo" ("Finally my Game") — a Godot 4.6 3D game project in early development.

**Main scene**: `main.tscn` — a `Node3D` root with a `MultiMeshInstance3D` child (box mesh, no instance data yet).

## Running the Game

Open the project in the Godot 4.6 editor and press F5 (run project) or F6 (run current scene). From the command line:

```bash
godot --path .          # Open in editor
godot --path . --headless  # Headless mode (e.g. for exports/CI)
```

## Tech Stack

- **Engine**: Godot 4.6
- **Renderer**: Forward Plus (DirectX 12 on Windows)
- **Physics**: Jolt Physics (3D)
- **Language**: GDScript (expected, as per Godot conventions)

## GDScript Conventions

- Use `snake_case` for variables and functions, `PascalCase` for classes and node names.
- Prefer `@export` annotations for inspector-exposed properties.
- Use signals for decoupled communication between nodes.
- Autoloads (Project > Project Settings > Autoload) are the standard pattern for global singletons (e.g., GameManager, AudioManager).
