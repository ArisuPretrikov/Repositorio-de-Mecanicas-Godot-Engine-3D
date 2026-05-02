# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Finalmente meu Jogo" ("Finally my Game") — a Godot 4.6 3D game project used as a mechanics sandbox. It combines a 3D player controller scene with a separate 2D LimboAI combat demo.

## Running the Game

Open in the Godot 4.6 editor and press F5 (run project) or F6 (run current scene).

```bash
godot --path .            # Open in editor
godot --path . --headless # Headless/CI mode
```

## Tech Stack

- **Engine**: Godot 4.6
- **Renderer**: Forward Plus
- **Physics**: Jolt Physics (3D)
- **AI**: LimboAI addon (behavior trees + hierarchical state machines)
- **Effects**: Shaker addon (screen shake, 2D/3D emitter-receiver architecture)

## Scene Architecture

### Main 3D Scene (`Main/main.tscn`)
The root `Node3D` composes:
- `Player` — instance of `Entidades/Player/player.tscn`
- `Mapa` — instance of `Mapa/mapa.tscn` (GridMap-based level)
- Four entity showcases: `EntidadeGlitch`, `EntidadeCorrompida`, `EntidadeContornada`, `EntidadeTudo` — each demonstrates a different custom GDShader
- `WorldEnvironment` with a dynamic sky shader (`Mapa/sky.gdshader`) that has day/night cycle parameters

### Player Controller (`Entidades/Player/player.gd`)
`CharacterBody3D` script driven by a **LimboAI Behavior Tree** embedded in `player.tscn`. The BT root is a Sequence with three branches:

1. **Movement selector** — picks Climb or Walk sub-sequence based on `_climbing` flag
2. **Current Action** — calls `tick_moving()`, `tick_crouch()`, `tick_climb_toggle()`
3. **States** — calls `tick_pose()`, `tick_animation()`

Camera: dual-camera setup — `Camera1P` (first-person) and `Camera3P` (child of Camera1P, third-person offset). Toggle via `camera_change` action (Y key). Mouse is captured by default; ESC toggles release.

Movement speeds: walk = 5.0, crouch = 2.0.

### LimboAI 2D Demo (`Demos/LimboAI/`)
A self-contained 2D wave-based combat game. Entry scene: `Demos/LimboAI/scenes/game.tscn`.

- **`scenes/game.gd`** — wave spawner: 10 waves of progressively harder enemies, 3-second delay between rounds, gong trigger starts each round
- **`agents/scripts/agent_base.gd`** — base `CharacterBody2D` with health, movement momentum, projectile spawning (`throw_ninja_star`, `spit_fire`), minion summoning, and knockback
- **`agents/player/player.gd`** — extends `agent_base`, uses `LimboHSM` with four states: Idle → Move → Attack → Dodge
- **`ai/tasks/`** — custom BT leaf nodes (`pursue.gd`, `in_range.gd`, `face_target.gd`, etc.)
- **`ai/trees/`** — `.tres` BehaviorTree resources, one per agent type (01–09)

Nine agent types each have a matching scene (`agents/`) and behavior tree (`ai/trees/`): Simple, Charger, Imp, Skirmisher, Ranged, Combo, Nuanced, Demon, Summoner.

Combat uses an Area2D hitbox/hurtbox pattern: `hitbox.gd` emits damage on `area_entered`; `hurtbox.gd` forwards it to the `Health` node (`health.gd`, `class_name Health`, signals: `death`, `damaged`).

## Autoloads

| Name | Path | Purpose |
|---|---|---|
| `Shaker` | `addons/shaker/…` | Global screen shake coordinator |
| `Signal_Debugger` | `addons/SignalVisualizer/…` | Signal visualization in editor dock |

## Input Actions

`move_forward` W · `move_back` S · `move_left` A · `move_right` D · `jump` Space · `crouch` Shift · `camera_change` Y

## Physics Layers

Layer 1: `Player` · Layer 2: `Mundo` (world geometry)

## GDScript Conventions

- `snake_case` for variables/functions, `PascalCase` for classes and node names
- `@export` for inspector-exposed properties
- Signals for decoupled node communication
- BT leaf nodes extend `BTAction` or `BTCondition` and implement `_tick() -> Status`
