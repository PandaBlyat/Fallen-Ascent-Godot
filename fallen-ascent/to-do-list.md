# Fallen Ascent — To-Do List

Running ledger of work that is **known to be needed** but is intentionally
out of scope for the current task. New entries get added here whenever an
agent identifies a gap that future work must close. Remove an entry only
when it's actually done.

Format: `[area] short description — why it matters / first hint at how`.

---

world map/colony map generation is just randomly patchy blobs.  It should be like a megastructure like Blame! almost like a maze with many shortcuts and rooms etc etc  (let's use placeholder art using code).
**PARTIAL FIX** — world map now uses BSP districts/corridors and colony terrain uses chamber/corridor/void/conduit generation. Keep tuning once full art/gameplay loop lands.

## Rendering & assets

- [ ] **Replace placeholder UI panel PNGs with real art.** Per-panel
      placeholder textures + descriptions live in `resources/ui/panels/`.
      ColonyHud / TechTreePanel load them through `_panel_textured_style`,
      so the moment a PNG is replaced with proper 48x48 9-slice art the
      panel re-skins. SettingsMenu and PauseOverlay still need wiring
      from their `.tscn` to the matching PNGs (`settings_menu.png`,
      `pause_overlay.png`).
- [ ] **Authoring water atlas art.** `water_atlas.png` now has 3 rows
      (deep/shallow/puddle) used by `TILE_WATER`, `TILE_WATER_SHALLOW`,
      `TILE_WATER_PUDDLE`. Placeholder cells are flat-tinted; the shader
      at `resources/shaders/water_tile.gdshader` keys ripple intensity
      off the atlas row. Tune palettes/animations once real art lands.
- [ ] **Move fog/lighting overlay data to a dirty-tile GPU mask pipeline.**
      Per-pixel `set_pixel` is gone — `FogOfWar` now writes both visibility
      and light masks straight into `PackedByteArray`s and uploads via
      `Image.create_from_data`, and the light buffer is gated by a
      `_light_dirty` flag so it only rebuilds on tile/structure/explored
      changes. Next step: keep dirty rects per refresh, update only changed
      mask regions, and push more LOS / falloff work into shaders.
- [ ] **Floor variation shader has fixed params.** `floor_variation.gdshader`
      now adds per-tile brightness/tint/wear hashed from world-tile coords
      via a single shared `ShaderMaterial` on every base TileMapLayer. Tune
      `brightness_min/max`, `wear_threshold`, `hue_jitter` once real art
      lands — current defaults are deliberately subtle.
- [x] **Swap `draw_rect` chunks for `TileMapLayer`.** Current `Chunk._draw`
      iterates 1024 cells per chunk per redraw. Won't scale to many visible
      chunks. Public API on `Chunk` (`get_tile/set_tile/SIZE/TILE_PIXELS`)
      is already shaped for this — swap rendering without touching callers.
- [x] **Author `resources/tiles/placeholder_tiles.tres`** — a `TileSet` of
      flat-color 16×16 cells so the `TileMapLayer` swap has data to point at.
- [ ] **Real pixel-art tileset + worker/item sprites.** All current visuals
      are flat-color placeholders.
- [x] **Static world-prop spawner/layer.** Placeholder atlas now exists at
      `resources/objects/placeholder_static_objects_atlas.png`, but there is
      now a deterministic `StaticPropManager` layer with mineable props,
      clustered placement, and tunable salvage drops.

## Persistence

- [ ] **Save / load system.** No serialization yet. Per CLAUDE.md, saves
      should store **diffs** vs. regenerated chunks, not raw chunks. Currently
      a mined wall reverts to wall when the chunk unloads and reloads — fine
      for the prototype loop, not fine for a real run.
- [ ] **Persist TechManager state** (wisdom + unlocked techs) when the save
      system is built. Use the ConfigFile pattern from SettingsManager as
      the interim shape: a `[research]` section with `wisdom` and an array
      of unlocked tech ids.
- [x] **Chunk-diff cache.** A `Dictionary[Vector2i, Dictionary[Vector2i, int]]`
      (chunk → local → tile) inside `ChunkManager` so mined cells persist
      across unload/reload during a session, even before the save system.

## Pathfinding & sim scaling

- [x] **Replace linear job-board scans with spatial / typed job queues.**
      Phase 2a: `JobBoard` now indexes pending jobs by chunk
      (`_pending_by_chunk`) and `claim_next_for` scans the 3x3 chunk
      neighborhood before falling back to a global scan. `blocked_until_msec`
      lifted onto the `Job` base class so per-job reachability cooldowns
      apply to every kind.
- [x] **Batch worker AI ticks (ambient bots).** Phase 2b: new
      `AIScheduler` autoload round-robins NeutralBot/HostileBot perception
      via `ai_tick(delta)`. Their per-instance `_perception_timer` nodes
      were retired. Worker keeps `_idle_cooldown`-driven IDLE pacing
      because it's intertwined with its idle-behavior state machine.
- [ ] **Replace full-region `AStarGrid2D` with chunked / hierarchical
      pathfinding** once the colony grows past a handful of workers. The
      current `Pathfinder._rebuild` walks every cell in the loaded region on
      any chunk load/unload.
- [ ] **Object pool for workers / items / projectiles** as soon as any of
      them exceeds ~100 live instances. Phase 2b shipped the
      `scripts/pool/NodePool.gd` infrastructure; concrete `ItemPool` /
      `WorkerPool` / `ProjectilePool` wiring still pending.
- [ ] **Ambient entity crowd path.** Neutral bots now sleep while idle and
      avoid duplicate path queries, but hundreds of ambient bots should move
      through a manager with batched thinking and `MultiMeshInstance2D` or
      another shared render path instead of one drawing `Node2D` per bot.
- [ ] **Combat follow-ups.** Object pool for hostiles once cap raised above
      ~30; ranged weapons (currently melee only); corpse → scrap drops on
      death; targeted hit zones replacing the random-limb roll inside
      `Worker._damage_limb`; a `CombatDirector` autoload to globally
      throttle attack resolution; faction designer for tunable hostile
      waves. (Phase 1 added a shared `EntityGrid` autoload covering the
      spatial-grid perception scan; combat queries now use it.)
- [x] **Pathfinder region-shift optimization.** Phase 1: `_region` grows
      monotonically and a persistent `_solid_cache` is replayed after
      `AStarGrid2D.update()` instead of refilling the full region from
      `is_walkable`.

## UI follow-ups

- [ ] **Persist user-dragged HUD panel positions.** ColonyHud now lets the
      player click-drag the top strip, worker list, and designation palette
      from their edges to relocate them. The chosen positions are only kept
      for the session — save them with the rest of UI prefs once the save
      system lands. See `_drag_offsets` in `scripts/ui/ColonyHud.gd`.
- [ ] **Teleporter block visualization.** Player can now left-click a
      teleporter tile (no entity under cursor) to block workers from
      walking onto / teleporting through it. Block state lives in
      `ChunkManager._blocked_teleporters` and renders as a red X in
      `SelectionController._draw_blocked_teleporters`. Replace with proper
      art once tile visuals firm up.


- [ ] **In-place dynamic refresh for the selection panel.** `_refresh_dynamic_status`
      currently skips the selection-panel rebuild while the mouse is over it
      to keep fabrication-spot craft buttons clickable. Side effect:
      progress meters / queued counts only update when the user moves the
      cursor off the panel. Next pass: keep the buttons alive between
      ticks and update label / meter values in place instead of nuking and
      re-creating the whole card.
- [x] **Re-purpose the Machine Room designation.** Replaced by Workshop Room
      (enclosed + door + light + workshop → speed buff; outside any room →
      debuff). Old Machine Room and Meditation Chamber kinds were renamed
      (Research Room) or removed (Machine Room → Workshop Room).
- [ ] **Crafting Bench UI parity.** Old `Id.FABRICATOR` (Crafting Bench) was
      stripped of its DATACORE/CHARGE_CELL production; the new
      `Id.FABRICATOR_ADVANCED` (Fabricator) covers that role. The Crafting
      Bench currently has no production wired up — the intent is "same UI as
      Crafting Spot but faster", which needs the craft-job dispatcher to
      treat both as crafted-object stations.

## World gen follow-ups

- [ ] **Water can carve through walls/rooms.** Lake/river/puddle generation
      runs only on `TILE_FLOOR` cells, so rivers stop at corridor walls and
      lakes can't intrude into chambers. Once it's gameplay-relevant,
      either let the water field overwrite walls (with intentional shore
      cleanup) or carve rivers into the chunk before rooms are placed.
- [ ] **Author real acid atlas art.** Rows 3-5 of `water_atlas.png` are flat
      green placeholders sized to the existing 16-mask layout; the shared
      `water_tile.gdshader` already handles palette/ripple per band. Replace
      with proper pixel art when the visual identity lands.
- [ ] **Author real grass / biomass art and persist grass diffs.** Grass
      overlay + biomass item cells are placeholder atlases only. Current grass
      growth/scraping is session-local generated state; save system should
      store grass add/remove diffs once persistence exists.

## Tech tree & economy follow-ups

- [ ] **Real art for new placeholder structures.** Meditation Pad and
      Replication Cradle currently reuse the existing flat-color squares in
      the multi-tile atlas; the wisdom badge and tech-tab icon also reuse
      existing UI atlas cells. Author dedicated cells in
      `resources/tiles/placeholder_atlas_multi_tile.png` and
      `resources/ui/placeholder_ui_atlas.png` when the visual identity firms
      up. (Per CLAUDE.md placeholder-atlas rule.)
- [ ] **Battery Bank** (Power Grid III) and **Long-range Scanner**
      (Sensors II) are stubs — nodes exist in the tech tree with wisdom
      cost but no BuildBlueprint id wired. Add the structures + recipes
      next pass.
- [x] **Mechanic Room limb-heal worker behavior.** See the rooms section.
      **Implemented v1:** valid Mechanic Rooms pulse limb repair to workers
      inside the room.
- [ ] **Tune the wisdom curve.** The 0.6 / sec base rate (+25% with Focused
      Mind) plus 8-14 s sessions was eyeballed. Once a real playthrough
      exists, tune session lengths, base rate, and tech costs together so
      Refining II + Power Grid II + Mechanic Dock + Replication Cradle lands
      around the intended several-hour mark.
- [ ] **Wisdom decay / mood gate.** Currently meditating is free and
      always positive. Consider a fatigue mechanic (consecutive sessions
      yield less) once players are exploiting it.

## Quick-fix session 2026-05-26 (later batch)

- [ ] **Swap mouse buttons setting.** `SettingsManager.swap_mouse_buttons`
      now flips the LMB/RMB roles. `primary_mouse_button()` returns the
      "select/cancel" button and `secondary_mouse_button()` returns the
      "place/order/drag" button. Used by `SelectionController`,
      `Designator`, and `ColonyHud` panel drag. Designation hotkeys
      (`designate_mine`, etc.) still go through their action bindings.
- [ ] **Tooltip dwell halved.** `ColonyTooltip.HOVER_DWELL_SECONDS` is now
      0.25 (was 0.5). Tune again once full art lands.
- [ ] **Workers can be paused per-bot.** New `Worker.set_paused/is_paused`
      gates the entire `_process` early; `state_label()` reads "paused".
      Toggle UI is a button at the top of the worker detail card
      (`ColonyHud._add_worker_pause_button`).
- [ ] **Discovered-area darkness lifted.** `FogOfWar.MEMORY_COLOR.a`
      dropped 0.80 → 0.55 and `LIT_MEMORY_MIN_ALPHA` 0.16 → 0.10. The new
      `SettingsManager.overall_darkness` multiplier (0.0–2.0) modulates
      all fog alpha at draw time, exposed as a slider in the Display tab.
- [ ] **Global Delete tool.** Per-tab "Remove" buttons (Zones,
      Rooms) are gone. A single big red "Delete" button at the end of the
      tab row enters `Designator.Mode.DELETE`, which on RMB removes the
      first hit among: pending build job → player-placed structure (with
      50% ingredient refund via `StructureManager.delete_structure_at`) →
      stockpile zone → room → pending mine/biomass order. The targeted
      tile gets a fading red overlay (`_delete_overlays` in
      StructureManager) for ~0.7s after removal.
- [ ] **Nearest-stockpile haul.** `StockpileManager._try_post_haul_for`
      picks the zone whose free cell is closest (Chebyshev) to the loose
      item, instead of the first zone in `zones` order. Items no longer
      trek across the colony when a nearer stockpile is open.
- [ ] **Panel drag is now RMB-anywhere.** `ColonyHud._on_drag_panel_input`
      grabs on the secondary mouse button anywhere in a HUD panel instead
      of LMB on the 8-px border. Buttons inside still consume LMB normally.

## Quick-fix session 2026-05-26

- [ ] **Teleporter pathfinding shortcut.** Pathfinder now treats teleporters
      as solid in the default A* grid so workers never wander through one
      mid-job and get warped off-task. A new `_astar_with_teleport` and
      `find_path_via_teleporter` cover the explicit "walk to a teleporter"
      use cases (charge-via-teleporter, socialize repath). Future work: use
      teleporters as actual shortcuts in long paths — would need a
      hierarchical pathfinder or a precomputed pair-link graph since
      destinations are currently random.
- [ ] **World-light texture refresh.** StructureManager now hooks
      `EventBus.visibility_changed` and calls `queue_redraw`, so generated
      lights paint their atlas cell the moment the player explores their
      tile. Previously the redraw only happened on door animations or new
      structures being placed, leaving big patches of "invisible" lights.
- [ ] **Jobs dropdown.** "jobs N" in the top strip is now a button. Click
      to see every pending job with a cancel (`x`) button. Uses
      `JobBoard.cancel_job(job)` + `JobBoard.describe_job(job)`. Active
      jobs (claimed by a worker) are tagged "active" so the player knows
      a cancel will yank the worker off-task. HaulJob cancel releases the
      stockpile reservation; if any new job type adds external bookkeeping
      it must be added to `cancel_job` too.
- [ ] **Worker limb panel.** The worker detail card now renders each limb
      as a name + percent + condition bar (color-coded green / amber / red).
      Added `Worker.limb_condition_ratios()` so the HUD doesn't have to
      re-parse the status lines.
- [ ] **Designation place modes are RMB-only.** Left-click in any active
      designation mode (paint, designate, place) now cancels — including the
      workshop / object placement modes that previously also placed on LMB.
      RMB drives every mode uniformly.
- [ ] **Floor variation shader pass 2.** `floor_variation.gdshader` now
      layers patch-scale brightness bands, coarse grime stipple, soft tile-
      edge shading, and occasional 1px chips on top of the existing wear /
      tint hash. Still pixel-art friendly (all hashes quantized, pixel-grid
      sampling). Tunable via `patch_scale`, `grime_*`, `crack_chance`,
      `edge_shade`. Visual identity will need another pass once real floor
      art lands.
- [ ] **Grass desaturated.** `grass_overlay.gdshader` mixes toward
      luminance via a `saturation` uniform (default 0.55) and applies a
      muted `mood_tint` so the placeholder grass reads as moss instead of
      neon. Tune both once real grass art lands.

## Recent quick-fix session notes

- [ ] **World-gen lights now reuse the explored-cells visibility gate** in
      `StructureManager._is_structure_draw_visible` (same path as player-placed
      structures). If draw-call cost on huge maps becomes a concern, swap the
      explored check for a chunk-level visible bucket instead of per-structure.
- [ ] **Build / repair durations were rescaled ~2.5x.** See
      `BuildBlueprint.build_duration` and `Worker.REPAIR_RECOVERY_PER_SEC`.
      Re-tune once a real economy/playthrough is on the floor.
- [ ] **New-game flow skips the world map.** `scripts/Main.gd` now pops a
      seed/size dialog directly and writes a synthetic SiteData to GameState.
      WorldMap.tscn is unreferenced from the main menu but still works if
      `change_scene_to_file` is called externally — delete the world-map
      scene/script once we're sure we don't want it back.
- [ ] **Speed control buttons and ColonyTooltip now read `selection_panel.png`**
      via local StyleBoxTexture builders (the buttons modulate the shared
      art to keep pause/active/hover distinguishable). Pull these into a
      shared helper alongside `ColonyHud._panel_textured_style` once we have
      another caller.
- [ ] **Damaged workers self-direct to a repair bench at ≤45% condition**,
      otherwise complain with a `_remember("Can't repair myself, no repair bench")`
      thought (throttled to every 18s). Researching now drains mood at 0.6/s
      and idle workers roll a 15% chance per idle tick to break for research
      (with a 45–90s cooldown). All of these are eyeballed — tune once the
      colony loop is balanced.
