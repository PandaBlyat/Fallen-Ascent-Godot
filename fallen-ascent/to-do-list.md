# Fallen Ascent — To-Do List

Running ledger of work that is **known to be needed** but is intentionally
out of scope for the current task. New entries get added here whenever an
agent identifies a gap that future work must close. Remove an entry only
when it's actually done.

Format: `[area] short description — why it matters / first hint at how`.

---

## Rendering & assets

- [ ] **Swap `draw_rect` chunks for `TileMapLayer`.** Current `Chunk._draw`
      iterates 1024 cells per chunk per redraw. Won't scale to many visible
      chunks. Public API on `Chunk` (`get_tile/set_tile/SIZE/TILE_PIXELS`)
      is already shaped for this — swap rendering without touching callers.
- [ ] **Author `resources/tiles/placeholder_tiles.tres`** — a `TileSet` of
      flat-color 16×16 cells so the `TileMapLayer` swap has data to point at.
- [ ] **Real pixel-art tileset + worker/item sprites.** All current visuals
      are flat-color placeholders.

## Persistence

- [ ] **Save / load system.** No serialization yet. Per CLAUDE.md, saves
      should store **diffs** vs. regenerated chunks, not raw chunks. Currently
      a mined wall reverts to wall when the chunk unloads and reloads — fine
      for the prototype loop, not fine for a real run.
- [ ] **Chunk-diff cache.** A `Dictionary[Vector2i, Dictionary[Vector2i, int]]`
      (chunk → local → tile) inside `ChunkManager` so mined cells persist
      across unload/reload during a session, even before the save system.

## Pathfinding & sim scaling

- [ ] **Replace full-region `AStarGrid2D` with chunked / hierarchical
      pathfinding** once the colony grows past a handful of workers. The
      current `Pathfinder._rebuild` walks every cell in the loaded region on
      any chunk load/unload.
- [ ] **Object pool for workers / items / projectiles** as soon as any of
      them exceeds ~100 live instances. Reserve `scripts/pool/`.

## Gameplay loop expansion

- [ ] **Worker selection + direct orders** (left-click select, right-click
      command). Job board stays primary; selection is an override layer.
- [ ] **Designation removal for stockpile zones** (no UI to delete a zone
      today).
- [ ] **Stockpile zone re-validation** when underlying tiles change (e.g.
      a designated floor cell becomes void/wall somehow). Currently
      `StockpileZone.cells` is frozen at creation.
- [ ] **Build job (place wall)** — closes the round-trip economy: scrap → wall.
- [ ] **Multiple item types and stacking.** Today only `Item.Kind.SCRAP`,
      one item per stockpile cell.
- [ ] **Job priorities.** Workers currently pick the Chebyshev-nearest
      unclaimed job. Designations need priorities (urgent mine vs. routine
      haul) and per-worker work types.
- [ ] **Worker needs** — power/charge, repair, "sleep" cycle. Sets up the
      AI director that CLAUDE.md flags as a future autoload candidate.
- [ ] **Combat + hostile entities.** Implies factions, damage, line-of-sight.

## UI

- [ ] **Replace the single debug label with a real HUD** — resource panel,
      worker list, current designation tool palette as actual buttons.
- [ ] **Designation tool palette** with on-screen buttons (today: hotkeys
      M / B / Esc only).
- [ ] **Tooltip on hover** showing tile type, occupant, designation status.
- [ ] **Audio settings** — master / music / SFX volume sliders in
      `SettingsMenu` once we have audio. Wire to AudioServer bus volumes
      and persist via `SettingsManager` (add a `[audio]` section).
- [ ] **Keybinding rebinder** — UI to remap actions in `project.godot`'s
      InputMap at runtime, saved per-action to `user://settings.cfg`.
- [ ] **Return to Main Menu** action — from ColonySite / WorldMap, route
      back to `Main.tscn` (currently the only way back is to quit).
- [ ] **Windowed resolution picker** in `SettingsMenu` — current settings
      ship display-mode + vsync + FPS only; resolution UX (custom vs.
      monitor-native list, what to do in fullscreen) needs its own pass.

## Tests / tooling

- [ ] **Determinism tests for procgen.** CLAUDE.md mentions these live next
      to the generator; not yet written. Bump
      `WorldGenerator.WORLDGEN_VERSION` when terrain output changes.
- [ ] **Headless smoke test** that boots `Main.tscn`, runs a fixed number of
      frames, and asserts no errors / no leaked nodes. Useful in CI.

## Known small bugs / cleanups

- [ ] **`Pathfinder._rebuild` reinitializes the whole AStarGrid2D** even when
      the loaded region only changed by one chunk. Could keep the grid and
      only flip solidness for newly loaded/unloaded cells.
- [ ] **Workers may path to a stockpile cell whose tile became unwalkable
      mid-haul.** `_replan` handles it by dropping in place; verify under
      stress.
- [ ] **Mining a tile a worker is currently standing on** — set_tile_at
      turns it to floor (no-op for walkability), but if we later add a tile
      type that's walkable-only-for-some, revisit this.
