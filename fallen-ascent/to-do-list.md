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

- [ ] **Move fog/lighting overlay data to a dirty-tile GPU mask pipeline.**
      `FogOfWar` still rebuilds CPU `Image` masks with per-pixel `set_pixel`
      and LOS loops. Next step: keep dirty rects, update only changed mask
      regions, and push more blend/falloff/noise work into shaders.
- [x] **Swap `draw_rect` chunks for `TileMapLayer`.** Current `Chunk._draw`
      iterates 1024 cells per chunk per redraw. Won't scale to many visible
      chunks. Public API on `Chunk` (`get_tile/set_tile/SIZE/TILE_PIXELS`)
      is already shaped for this — swap rendering without touching callers.
- [x] **Author `resources/tiles/placeholder_tiles.tres`** — a `TileSet` of
      flat-color 16×16 cells so the `TileMapLayer` swap has data to point at.
- [ ] **Real pixel-art tileset + worker/item sprites.** All current visuals
      are flat-color placeholders.
- [ ] **Static world-prop spawner/layer.** Placeholder atlas now exists at
      `resources/objects/placeholder_static_objects_atlas.png`, but there is
      no separate static object placement/rendering layer yet. Add one before
      tables, broken consoles, machine husks, and similar props become real
      map entities.

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

- [ ] **Replace linear job-board scans with spatial / typed job queues.**
      `JobBoard.claim_next_for` still scans all pending jobs per worker poll.
      Hundreds of workers plus thousands of designations need job buckets by
      kind/priority/chunk, with reachability cooldowns stored per job.
- [ ] **Batch worker AI ticks.** Workers still own one `_process` each.
      Current patches reduce wake storms and crowd scans, but hundreds of
      workers should use staggered think intervals or a colony AI scheduler
      for job polling, needs checks, and low-priority idle behavior.
- [ ] **Replace full-region `AStarGrid2D` with chunked / hierarchical
      pathfinding** once the colony grows past a handful of workers. The
      current `Pathfinder._rebuild` walks every cell in the loaded region on
      any chunk load/unload.
- [ ] **Object pool for workers / items / projectiles** as soon as any of
      them exceeds ~100 live instances. Reserve `scripts/pool/`.
- [ ] **Ambient entity crowd path.** Neutral bots now sleep while idle and
      avoid duplicate path queries, but hundreds of ambient bots should move
      through a manager with batched thinking and `MultiMeshInstance2D` or
      another shared render path instead of one drawing `Node2D` per bot.
- [ ] **Combat follow-ups.** Object pool for hostiles once cap raised above
      ~30; ranged weapons (currently melee only); corpse → scrap drops on
      death; targeted hit zones replacing the random-limb roll inside
      `Worker._damage_limb`; a `CombatDirector` autoload to globally
      throttle attack resolution; spatial grid for perception scans;
      faction designer for tunable hostile waves.
- [ ] **Pathfinder region-shift optimization.** Today, when the camera pans
      and the AStarGrid2D's bounding region shifts (even by one chunk), the
      grid is fully rebuilt because `AStarGrid2D.region = ...` then `update()`
      wipes all solidness. Either grow the region without ever shrinking,
      or keep our own solidness map and re-apply after `update()` only for
      cells in the kept range.

## Tech tree & economy follow-ups

- [ ] **Real art for new placeholder structures.** Meditation Pad and
      Sentience Cradle currently reuse the existing flat-color squares in
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
      Refining II + Power Grid II + Mechanic Dock + Sentience Forge lands
      around the intended several-hour mark.
- [ ] **Wisdom decay / mood gate.** Currently meditating is free and
      always positive. Consider a fatigue mechanic (consecutive sessions
      yield less) once players are exploiting it.

