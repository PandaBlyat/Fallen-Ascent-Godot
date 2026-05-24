# Fallen Ascent — Project Conventions

> **Before you start a task, read `to-do-list.md`.** That file is the
> running ledger of work that is known to be needed but is intentionally
> out of scope of past sessions. When *this* session identifies anything
> in the same category — a real need that you can't address right now —
> append it there before you finish. The to-do list is how we avoid
> forgetting things between sessions.
>Install any tools you need to better help you code/edit godot project.
## Project overview

Fallen Ascent is a 2D colony sim set inside a vast, BLAME!-inspired megastructure.
Players manage a settlement of sentient robots in a post-post-apocalyptic world.
Built with Godot 4.4 (Forward+ renderer), GDScript, targeting PC only. All art
in the prototype is **placeholder** — flat-colored tiles drawn via a `TileSet`
of solid-color textures, swapped out for real pixel art later.

Design influences: Kenshi, RimWorld, Dwarf Fortress, Cataclysm: DDA and factorio.
Far-future stretch: a Kenshi-style RPG mode controlling a single entity.

**Optimization is priority #1.** Every system is chosen with later scaling in
mind. When in doubt, prefer the cheaper approach now and measure before
"improving."

UPDATE THIS FILE WHENEVER NEEDED.
---

## Folder structure

```
fallen-ascent/
├── project.godot                # engine config, autoloads, input map
├── CLAUDE.md                    # this file
├── scenes/                      # .tscn files, grouped by domain
│   ├── Main.tscn                # entry point — sets seed, loads world map
│   ├── world/
│   │   └── WorldMap.tscn        # overview map + site selection UI
│   └── colony/
│       └── ColonySite.tscn      # chunked tilemap + camera + HUD
├── scripts/                     # .gd files, mirror scenes/ layout
│   ├── autoload/
│   │   ├── GameState.gd         # current world seed, selected site, speed
│   │   └── EventBus.gd          # global signal hub (loose coupling)
│   ├── world/
│   │   ├── SiteData.gd          # Resource — per-site seed, biome, score
│   │   ├── WorldGenerator.gd    # deterministic overview-map procgen
│   │   └── WorldMap.gd          # renders overview, handles click-to-select
│   ├── colony/
│   │   ├── ColonySite.gd        # owns chunk manager + camera
│   │   ├── ChunkManager.gd      # streams chunks around camera
│   │   ├── Chunk.gd             # 32×32 tile chunk
│   │   └── TerrainGenerator.gd  # per-chunk noise → tile id
│   ├── camera/
│   │   └── CameraController.gd  # pan / zoom / edgescroll
│   └── ui/
│       ├── SpeedControls.gd     # pause / 1× / 2× / 3× buttons
│       └── SiteTooltip.gd       # hover info on world map
└── resources/
    └── tiles/
        └── placeholder_tiles.tres   # TileSet of flat-color 16×16 cells
```

Naming convention for script roles:
- `*Generator` — pure (or near-pure) producer of data, no scene-tree lifecycle.
- `*Manager`   — owns the lifecycle of a collection of nodes/resources.
- `*Controller`— translates input/state into behavior on a single node.
- `*Data`      — `Resource` subclass holding typed, savable state.

---

## Coding standards

- **GDScript, always static-typed.** `func foo(x: int) -> Vector2i:`. The only
  untyped `var` allowed is a one-off local where the type is obvious from the
  RHS.
- **Naming.** `snake_case` for files / vars / functions, `PascalCase` for
  classes / scenes / Resources, `SCREAMING_SNAKE_CASE` for constants.
- **`class_name` sparingly.** Add it only when a script is referenced by other
  scripts as a type. Otherwise omit, to keep the global namespace clean.
- **`@export` / `@onready`.** `@export` for any value a designer should tweak
  in the inspector. `@onready` for child-node refs. Never `get_node()` inside
  `_process` / `_physics_process`.
- **Signals before refs.** Cross-system communication goes through `EventBus`.
  Intra-scene communication uses local signals between sibling nodes.
- **No business logic in per-frame callbacks** unless it actually needs
  per-frame work. Prefer `Timer`, signals, or `await`. If you must use
  `_process`, gate the heavy bits behind a "dirty" flag or visibility check.
- **`Vector2i` for grid coords, `Vector2` for pixel-space.** Mixing them is the
  #1 source of off-by-one bugs in procgen.

---

## Autoloads (keep this list short)

Current autoloads, in load order:

1. **`EventBus`** (`scripts/autoload/EventBus.gd`) — declares every
   cross-system signal in one place. No state, no logic. Read the header
   comment of `EventBus.gd` for the signal catalogue.
2. **`GameState`** (`scripts/autoload/GameState.gd`) — holds the global
   ambient state that almost every system needs:
   - `world_seed: int`
   - `selected_site: SiteData`
   - `game_speed: float`  (0.0 = paused; speed is applied via
     `Engine.time_scale` so all sim systems pick it up for free)

   Setters emit the matching `EventBus` signal — never write directly to
   these fields from outside, always go through the setter.

**Bar for adding a new autoload:** it must be needed by ≥3 unrelated scenes
*and* it must not fit comfortably inside `GameState`. Otherwise, instance it
where it's used. Save system / pathfinding / AI director will probably each
warrant their own — when they're built, not before.

---

## Optimization guidelines

- **Tiles render through `TileMapLayer`**, never per-tile `Sprite2D`. The
  batched draw path is the only one that scales to the megastructure sizes we
  want.
- **Colony world is chunked** (32×32 tiles, `Chunk.SIZE` is the source of
  truth). `ChunkManager` only keeps chunks within `view_radius` of the camera
  in the scene tree; others are freed.
- **Procgen is deterministic from a seed.** Never serialize generated tiles
  until they've been modified by gameplay — regenerate from `(world_seed,
  chunk_coord)` on demand. Saves should store *diffs*, not raw chunks.
- **Avoid per-frame allocations.** Reuse `Vector2i` arrays, `PackedInt32Array`,
  etc. across calls when possible.
- **Object pooling** for any entity that will exist in >100 instances (robots,
  items, projectiles). Not needed yet, but reserve `scripts/pool/` for it when
  it is.
- **Profile before optimizing.** Godot's built-in profiler +
  `Performance.get_monitor()` for FPS / draw calls / objects. Never optimize
  blind.

---

## Adding new features without breaking things

- **New cross-system signal?** Declare it on `EventBus`, with a one-line
  comment describing the payload contract. Update the catalogue at the top of
  `EventBus.gd`.
- **New autoload?** Justify it against the bar in the autoloads section. If
  it's borderline, instance it locally first.
- **New scene?** Drop it under the matching `scenes/<domain>/` and put its
  script under the parallel `scripts/<domain>/` path. Don't co-locate scripts
  with scenes — easier to grep, and avoids `.import`-noise in the scripts dir.
- **Touching procgen?** Bump `WorldGenerator.WORLDGEN_VERSION` so old saves are
  detectable. Determinism tests (when we have them) live next to the generator.
- **Touching `GameState` or `EventBus`?** Treat it like a public API change —
  expect every system to be affected. Search for usages first.

---

## Godot-specific gotchas

- **Don't use `@tool`** unless the script must run in-editor. It doubles your
  debugging surface (in-editor crashes are worse than runtime ones).
- **`_process(delta)` runs every frame for every node in the tree**, even when
  off-screen. Gate heavy work with `visible`, chunk-activity flags, or just
  don't add `_process` at all.
- **`queue_free()` is deferred** until end-of-frame. Don't read refs to a
  queue-freed node in the same frame; use `is_instance_valid()` if unsure.
- **Prefer `Resource` subclasses over `Dictionary`** for typed game data
  (`SiteData`, future `RobotStats`, etc.). You get autocompletion, type
  checking, and free disk serialization.
- **`randi()` is global and not seeded by default.** Use a local
  `RandomNumberGenerator` with an explicit `seed` for anything that must be
  reproducible. Mix seeds via `hash([world_seed, chunk_coord.x, chunk_coord.y])`.
- **`change_scene_to_file` runs deferred.** Anything you set on `GameState`
  *before* the call will be visible to the new scene's `_ready`.
