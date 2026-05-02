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

## Project Structure

```
addons/         # Third-party plugins (LimboAI, Shaker, SignalVisualizer, etc.)
assets/         # Raw asset files (textures, audio, models — currently empty placeholder)
components/     # Game components — each folder is a self-contained scene + script + resources
  ├── main/             # Entry scene (main.tscn)
  ├── mapa/             # GridMap level + sky shader
  ├── player/           # Player character (CharacterBody3D + LimboAI BT + AnimationTree)
  ├── horse/            # Mountable horse (CharacterBody3D + LimboAI BT + AnimationTree)
  ├── entidade_glitch/        # Glitch shader showcase entity
  ├── entidade_corrompida/    # Corruption shader showcase entity
  ├── entidade_contornada/    # Outline shader showcase entity
  └── entidade_tudo/          # Combined shader showcase entity
demos/          # Self-contained demos (LimboAI 2D combat, SignalVisualizer)
shared/         # Reusable scripts (autoload/, utils/) — placeholder for future
```

## Scene Architecture

### Main 3D Scene (`components/main/main.tscn`)
The root `Node3D` composes:
- `Player` — instance of `components/player/player.tscn`
- `Mapa` — instance of `components/mapa/mapa.tscn` (GridMap-based level)
- `Horse` — instance of `components/horse/Horse.tscn`
- Four entity showcases: `EntidadeGlitch`, `EntidadeCorrompida`, `EntidadeContornada`, `EntidadeTudo` — each demonstrates a different custom GDShader
- `WorldEnvironment` with a dynamic sky shader (`components/mapa/sky.gdshader`) that has day/night cycle parameters

### Player Controller (`components/player/player.gd`)
`CharacterBody3D` script driven by a **LimboAI Behavior Tree** embedded in `player.tscn`. The BT root is a Sequence with three branches:

1. **Movement selector** — picks Climb or Walk sub-sequence based on `_climbing` flag
2. **Current Action** — calls `state_update_moving()`, `state_update_crouch()`, `state_update_climb_toggle()`
3. **States** — calls `state_update_pose()`, `state_update_animation()`, `state_update_body_pivot()`, `state_update_stamina()`, `state_update_exhaustion()`

Camera: dual-camera setup — `Camera1P` (first-person) and `Camera3P` (child of Camera1P, third-person offset). Toggle via `camera_change` action (Y key). Mouse is captured by default; ESC toggles release.

Movement speeds: walk = 5.0, run = 9.0, crouch = 2.0, mount/mount_run = 6.0/12.0.

### Horse (`components/horse/horse.gd`)
`CharacterBody3D` with its own LimboAI BT (`horse_behavior_tree.tres`) that calls `tick_movement(delta)` and `tick_animation(delta)`. Uses an inline `AnimationTree` BlendTree (Idle/Walk/Fall + TimeScale).

Mount flow: player presses **F** with `RayCastInteract` (layer Cavalo) hitting the horse → `mount_on(horse)` → player snaps to `Pivot` Marker3D, collisions disabled. Player input (`W`, `A/D`, `Shift`, `Space`) is read by the horse's `_handle_mounted_input()` while ridden. Press **F** again to dismount.

### LimboAI 2D Demo (`demos/LimboAI/`)
A self-contained 2D wave-based combat game. Entry scene: `demos/LimboAI/scenes/game.tscn`.

- **`scenes/game.gd`** — wave spawner: 10 waves of progressively harder enemies, 3-second delay between rounds, gong trigger starts each round
- **`agents/scripts/agent_base.gd`** — base `CharacterBody2D` with health, movement momentum, projectile spawning, minion summoning, and knockback
- **`agents/player/player.gd`** — extends `agent_base`, uses `LimboHSM` with four states: Idle → Move → Attack → Dodge
- **`ai/tasks/`** — custom BT leaf nodes (`pursue.gd`, `in_range.gd`, `face_target.gd`, etc.)
- **`ai/trees/`** — `.tres` BehaviorTree resources, one per agent type (01–09)

Combat uses an Area2D hitbox/hurtbox pattern: `hitbox.gd` emits damage on `area_entered`; `hurtbox.gd` forwards it to the `Health` node.

## Autoloads

| Name | Path | Purpose |
|---|---|---|
| `Shaker` | `addons/shaker/…` | Global screen shake coordinator |
| `Signal_Debugger` | `addons/SignalVisualizer/…` | Signal visualization in editor dock |

## Input Actions

`move_forward` W · `move_back` S · `move_left` A · `move_right` D · `jump` Space · `crouch` C · `run` Shift · `camera_change` Y · `interact` F

## Physics Layers

Layer 1: `Player` · Layer 2: `Blocos` · Layer 3: `Blocos Escalaveis` · Layer 4: `Cavalo`

## GDScript Conventions

- `snake_case` for variables/functions, `PascalCase` for classes and node names
- `@export` for inspector-exposed properties
- Signals for decoupled node communication
- BT leaf nodes extend `BTAction` or `BTCondition` and implement `_tick() -> Status`
- BT method calls go through `BTCallMethod` with `node = NodePath(".")` (calls on the agent)
