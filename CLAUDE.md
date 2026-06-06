# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4 (GDScript) self-contained interactive character scene. Pure built-ins, no plugins.
Designed to be instanced into a larger VN/eroge game as a module.

## Running

Open `project.godot` in Godot 4 editor and press F5, or from the terminal:

```
godot --path . scenes/character_scene.tscn
```

## Architecture

```
scenes/character_scene.tscn     full node tree; all signal connections live here
scripts/character_controller.gd state machine, blink timer, zone/button handlers, signal emitter
scripts/reaction_data.gd        ReactionData.REACTIONS dict — only place to edit text strings
assets/sprites/                 spritesheet PNGs (empty until real assets are added)
```

### Node tree

```
CharacterScene (Node2D) ← character_controller.gd
├── Character (Node2D)
│   ├── Sprite (AnimatedSprite2D)
│   └── ClickZones (Node2D)
│       ├── HeadZone  (Area2D + CollisionShape2D)
│       ├── BodyZone  (Area2D + CollisionShape2D)
│       └── LapZone   (Area2D + CollisionShape2D)
├── BlinkTimer (Timer, one_shot=true)
└── UI (CanvasLayer)
    └── MenuButtons (VBoxContainer)
        ├── PetButton / TalkButton / GiftButton
```

### State machine

Two states in `character_controller.gd`: `IDLE` and `REACTING`.
`trigger_reaction()` is a no-op when already `REACTING` — no queuing, reactions are dropped.
`BlinkTimer` only fires the `blink` animation during `IDLE`; it is stopped on reaction entry and
re-armed on return to idle.

### Signals emitted (parent scene hooks)

```gdscript
signal zone_clicked(zone_name: String)          # "head" | "body" | "lap"
signal reaction_started(reaction_id: String, text: String)
signal reaction_finished(reaction_id: String)
signal menu_action(action_id: String)           # "pet" | "talk" | "gift"
```

### Animations required on AnimatedSprite2D

| Name | Loop | Trigger |
|------|------|---------|
| `idle` | yes | default |
| `blink` | no | BlinkTimer (3–8 s) |
| `react_head` | no | HeadZone click/touch |
| `react_body` | no | BodyZone click/touch |
| `react_lap` | no | LapZone click/touch |
| `react_pet` | no | Pet button |
| `react_talk` | no | Talk button |
| `react_gift` | no | Gift button |

### Adding a reaction

1. Add an entry to `ReactionData.REACTIONS` in `scripts/reaction_data.gd`.
2. Add the matching animation to the SpriteFrames resource on `Sprite`.
3. Call `trigger_reaction("your_key")` from a new zone handler or button handler in
   `character_controller.gd`, and wire the signal in `character_scene.tscn`.

## Asset Setup Checklist

Steps to replace placeholder sprites with real assets:

1. **Import spritesheet** — drop PNG into `assets/sprites/`. In the Import dock set
   Filter = Nearest for pixel art, or leave default for smooth VN style.
2. **Create SpriteFrames** — select `Character/Sprite` → Frames property → New SpriteFrames.
3. **Add all 8 animations** from the table above. Loop only `idle`; all others are one-shot.
   Typical FPS: 8–12 for reactions, 2–4 for idle sway.
4. **Assign frame ranges** — use the SpriteFrames editor's "Add frames from sprite sheet"
   to slice each animation out of the sheet.
5. **Fit CollisionShapes** — with sprites in place, adjust each `CollisionShape2D` under
   HeadZone / BodyZone / LapZone to cover the correct anatomy. `RectangleShape2D` works
   well for broad zones.
6. **Reposition MenuButtons** — move `UI/MenuButtons` to desired screen position
   (e.g. anchor to bottom-right).
7. **Smoke test** — run scene, click each zone and each button, confirm reactions play and
   `reaction_started` / `reaction_finished` signals fire. Wait 3–8 s to confirm blink fires.
