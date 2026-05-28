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

**Placeholder atlas rule.** Whenever a new item, resource, static object, or
tile is added, also add a flat-color placeholder entry for it:
- Connected floor-family terrain goes in `resources/tiles/floor_base_atlas.png`
  using the 4-bit `N/E/S/W = 1/2/4/8` mask layout documented beside the PNG.
- Connected water and acid both live in `resources/tiles/water_atlas.png` using
  the same 4-bit mask layout, with one atlas row per depth band:
  `y=0` deep water (impassable), `y=1` shallow water (walkable-but-slow),
  `y=2` water puddle (walkable), `y=3` deep acid (impassable, caustic),
  `y=4` shallow acid (walkable-but-slow + damage),
  `y=5` acid puddle (walkable + slight damage). The `water_tile.gdshader`
  routes palette + ripple style off the row.
- Connected wall-family terrain goes in one wall atlas per wall type, e.g.
  `wall_basic_atlas.png`, `wall_rich_atlas.png`, or
  `wall_service_core_atlas.png`.
- Rust visuals go in `resources/tiles/rust_overlay_atlas.png`; rust draws over
  floor, not as a standalone base tile.
- Workshop structures go in `resources/objects/workshops_atlas.png` using
  64 px cells. The cell order is documented beside the PNG and maps through
  `BuildBlueprint.workshop_atlas_index`.
- Door animation states go in `resources/objects/doors_atlas.png`.
- Crafted placeable objects that are not workshops go in
  `resources/objects/craftable_objects_atlas.png` using 32 px cells.
- Static world props that are not terrain, workshops, craftable objects,
  items, UI icons, or entities go in
  `resources/objects/placeholder_static_objects_atlas.png`.
- Loose items and materials go in `resources/items/placeholder_items_atlas.png`.
- Workers go in `resources/entities/worker_atlas.png`; neutral/hostile bots go
  in `resources/entities/bots_atlas.png`.
- Base floor variation is GPU-side via `resources/shaders/floor_variation.gdshader`
  — a single shared `ShaderMaterial` on every chunk's base `TileMapLayer`
  hashes world-tile coords to vary brightness/tint and dust on a fraction
  of tiles. Tune via uniforms; don't paint dozens of variation atlases.
- UI command icons go in `resources/ui/placeholder_ui_atlas.png`.
- Achievement icons go in `resources/ui/achievements_atlas.png` — one row of
  32 px cells; cell `i` maps to `AchievementManager.ACHIEVEMENTS[i]` (same
  order). Append-only; see the sibling `.md`.
- UI panel backgrounds go in `resources/ui/panels/<panel_name>.png` (48x48
  with 16 px corners for 9-slice). Each PNG has a sibling `.md`
  describing what panel it skins. `ColonyHud._panel_textured_style` loads
  them at runtime, with the legacy flat-color style as fallback.
- If terrain atlas cells change, update `resources/tiles/placeholder_tiles.tres`
  so the new tile id has a TileSet atlas entry. Keep cells 32x32 aligned.
- Treat placeholder atlases as append-only. Add new cells by expanding the
  canvas or filling unused aligned cells; do not reshuffle or repaint existing
  cells unless every coordinate reference is updated in the same change.

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
		└── placeholder_tiles.tres   # TileSet of flat-color 32×32 cells
```

Naming convention for script roles:
- `*Generator` — pure (or near-pure) producer of data, no scene-tree lifecycle.
- `*Manager`   — owns the lifecycle of a collection of nodes/resources.
- `*Controller`— translates input/state into behavior on a single node.
- `*Data`      — `Resource` subclass holding typed, savable state.

## Designation tabs

The colony palette is grouped into five top-level tabs (`ColonyHud._set_tab`):

- **Orders** — task overlays (mine).
- **Zones** — stockpile paint/remove.
- **Rooms** — Rimworld-style room designations: Dock, Research, Mechanic, Workshop.
- **Workshops** — worker-operated structures (dock bed, repair bench, research bench,
  crafting spot/bench, sensor, extractor, charge, assembler press, mechanic dock,
  fabricator, replication cradle).
- **Building** — wraps four subtabs (`ColonyHud._render_current_tab`):
  - **General** — wall, door, outlet extension.
  - **Storage** — storage bin.
  - **Visibility** — small/large light devices, rudimentary sensor.
  - **Objects** — placeholder for future crafted-object placements.

There is no per-tab Cancel button: a left-click on any world tile while a
designation mode is active cancels it (see `SelectionController._unhandled_input`),
and Esc still cancels through `Designator.cancel_active()`.

## Bot mood + needs

`Worker._mood` is a 0..100 stat. The baseline is `_mood_baseline` (default
`MOOD_BASELINE = 80`, but personality/parts shift it) and recovery is scaled by
`_mood_recovery_mult`. `_unsatisfied_needs` is recomputed every frame from
`RoomManager`. Each unmet need drains mood at `MOOD_NEED_DECAY_PER_SEC`; when
satisfied, mood drifts back to baseline. Add new needs by appending to
`_unsatisfied_needs` in `Worker._update_mood` — the HUD renders them
automatically.

`Worker.Personality` has **9** values (Dutiful, Grumpy, Cheerful, Philosophical,
Paranoid, Stoic, Nostalgic, Competitive, Glitchy) and maps 1:1 to
`WorkerLines` dialogue buckets and `WorkerLoadout.PERSONALITY_MODS`. Keep these
three in sync when adding a personality.

## Worker parts, skills, and embark

Workers are built from a Cogmind-style part system. A bare `Worker` is a
**shell** (`PartDatabase.SHELL`): slow, low bash, tiny carry. Parts slot into
five categories (`PartDatabase.Slot`: Power/Propulsion/Manipulation/Utility/
Weapon) across Tiers 1–5.

- `scripts/colony/parts/PartDatabase.gd` — static, append-only part registry +
  `accumulate()` (shell + part mods → stats dict). Add parts by appending to
  `PARTS`; never reshuffle ids (saved loadouts resolve by id).
- `scripts/colony/parts/WorkerLoadout.gd` — `Resource` holding name,
  personality, `part_ids` (parallel to `SLOT_LAYOUT`), `skills`, `specialty`.
  `derive()` folds parts + skills + a per-role `buff` + personality into one flat
  stats dict. `SPECIALTIES` entries carry a `buff` (small role bonus added in
  `derive()`) and a `desc` (shown as the embark role tooltip via `role_desc()`).
- `Worker.apply_loadout(loadout)` pushes derived stats onto the live worker
  (move/work/carry/hp/bash/armor/sight/energy/mood). Workers spawned WITHOUT a
  loadout keep the original pre-parts balance, so cradle spawns and old saves
  don't regress. Loadouts are persisted in `capture_save`/`restore_save`.
- **Body-part condition.** Each equipped part has its own condition (0..100),
  tracked in `Worker._part_conditions` keyed by `SLOT_LAYOUT` index. Combat,
  acid, and wear damage a random equipped part (`_damage_part`); Mechanic Docks
  repair them (`repair_parts_external`). A part-less shell has no part conditions
  and falls back to the overall `_condition` meter. The worker stat panel renders
  one bar per part via `Worker.part_condition_entries()` (no more abstract limbs).

Embark flow: `EmbarkScreen` (per-run pool points) → `embark_confirmed(Array[
WorkerLoadout])` → `GameState.embark_loadouts` → `ColonySite` →
`WorkerSpawner.spawn(..., loadouts)`. Achievement points
(`AchievementManager`) permanently unlock higher part tiers, extra worker
slots, and **manual personality choice** from the embark store. By default each
worker's personality is randomized and can only be rerolled (per worker or via
"Randomize All"); randomizing also rolls a budget-fitting random part loadout
(parts start empty). **Names** come from `WorkerSpawner.BOT_NAMES` (the
single source) and the embark screen draws from that same pool.

`RoomManager` owns the list of player-designated rooms. Kinds:
- `DOCK_ROOM` — 1×2+ area containing at least one Dock Bed (or Mechanic Dock).
  Assigned to a single worker via `ensure_dock_room_for`.
- `RESEARCH_ROOM` — must contain a Research Bench (formerly Meditation Pad).
- `MECHANIC_ROOM` — must contain a Mechanic Dock; repairs damaged body parts of occupants.
- `WORKSHOP_ROOM` — must be enclosed by walls (or natural wall tiles) + at
  least one door on the perimeter, contain a placed light source object, and
  contain a workshop structure. Workshops inside a valid Workshop Room get a
  small speed buff; workshops outside any room suffer a small debuff
  (`workshop_speed_multiplier_at`).

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
