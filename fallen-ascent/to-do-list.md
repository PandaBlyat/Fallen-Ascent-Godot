# Fallen Ascent — To-Do List

Running ledger of work that is **known to be needed** but is intentionally
out of scope for the current task. New entries get added here whenever an
agent identifies a gap that future work must close. Remove an entry only
when it's actually done.

Format: `[area] short description — why it matters / first hint at how`.

---

world map/colony map generation is just randomly patchy blobs.  It should be like a megastructure like Blame! almost like a maze with many shortcuts and rooms etc etc  (let's use placeholder art using code). 

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
- [ ] **Pathfinder region-shift optimization.** Today, when the camera pans
      and the AStarGrid2D's bounding region shifts (even by one chunk), the
      grid is fully rebuilt because `AStarGrid2D.region = ...` then `update()`
      wipes all solidness. Either grow the region without ever shrinking,
      or keep our own solidness map and re-apply after `update()` only for
      cells in the kept range.

## Gameplay loop expansion

- [ ] **Job priorities.** Workers currently pick the Chebyshev-nearest
      unclaimed job. Designations need priorities (urgent mine vs. routine
      haul) and per-worker work types.
- [ ] **Worker needs** — power/charge, repair, "sleep" cycle. Sets up the
      AI director that CLAUDE.md flags as a future autoload candidate.
- [ ] **Combat + hostile entities.** Implies factions, damage, line-of-sight.
- [ ] **More item kinds for real gameplay.** `Item.Kind.COMPONENT` exists
      as a placeholder alongside `SCRAP`, but nothing produces components
      yet. Mining could rarely drop one; recipes / build costs that mix
      kinds would force varied stockpiles.
- [ ] **Multi-tile structures.** `BuildJob` places single walls today.
      Doors, multi-tile machines, lights, conveyors all want a different
      shape (designate footprint, multiple ingredients, blueprints).
- [ ] **Construction blueprints / ghost preview.** A faded outline at the
      build target before completion would help readability.
- [ ] **Selection box / multi-worker selection.** Currently the
      `SelectionController` picks a single worker on left-click. Drag-box
      select would let players issue group orders.
- [ ] **Direct-order queueing.** A worker issued a manual order today
      abandons it as soon as the player issues a new one. Adding a small
      queue (Shift-right-click appends) would feel more like RimWorld /
      Factorio.

## UI

- [ ] **Replace the single debug label with a real HUD** — resource panel,
      worker list, current designation tool palette as actual buttons.
- [ ] **Designation tool palette** with on-screen buttons (today: hotkeys
      M / B / N / X / Esc only).
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
- [ ] **Selected-worker info panel.** Now that workers can be selected,
      show their current job / carried item / state so the player has
      feedback on direct orders.

## Tests / tooling

- [ ] **Determinism tests for procgen.** CLAUDE.md mentions these live next
      to the generator; not yet written. Bump
      `WorldGenerator.WORLDGEN_VERSION` when terrain output changes.
- [ ] **Headless smoke test** that boots `Main.tscn`, runs a fixed number of
      frames, and asserts no errors / no leaked nodes. Useful in CI.

## Known small bugs / cleanups

- [ ] **`Pathfinder._rebuild` reinitializes the whole AStarGrid2D** even when
      the loaded region only changed by one chunk. Could keep the grid and
      only flip solidness for newly loaded/unloaded cells. (Partial fix
      landed: same-region rebuilds are now incremental; region changes are
      still full.)
- [ ] **Workers may path to a stockpile cell whose tile became unwalkable
      mid-haul.** `StockpileManager` now revalidates zones on tile changes,
      but verify under stress with simultaneous mining + hauling.
- [ ] **Mining a tile a worker is currently standing on** — set_tile_at
      turns it to floor (no-op for walkability), but if we later add a tile
      type that's walkable-only-for-some, revisit this.
- [ ] **Two workers can hold the same direct-order job for one frame** if
      `command_mine`/`command_build` is called while another worker already
      had it claimed. Today we cancel-then-re-add the designation so the
      previous claimer drops it via `job_cancelled`. Race-condition-prone
      if multi-issue happens in one frame.
- [ ] **`BuildJob.source_item` might become invalid before pickup** if a
      different worker hauls it away. `_begin_build` re-finds the material
      at claim time but doesn't re-find if the chosen item disappears
      between `_begin_build` and `_pickup_for_build`.
- [ ] **Borderless-fullscreen on Linux/Wayland** may behave differently
      from X11/Windows. SettingsManager now uses `WINDOW_MODE_FULLSCREEN`
      for FULLSCREEN; revisit if users report regressions on a specific
      platform.

changing from fullscreen/wincowed/borderless doesnt do anything.   **FIXED** —
the previous code set `WINDOW_MODE_EXCLUSIVE_FULLSCREEN` which silently
no-ops on some platforms; we now reset to windowed before reapplying the
target mode and use `WINDOW_MODE_FULLSCREEN` (borderless fullscreen).

when doing an action/order and player presses "esc" it opens the settings instead of cancelling action/order.  **HANDLED** — Designator already
consumes `cancel_mode` when its mode != NONE before PauseOverlay sees it.
If this still happens, check the input ordering in the scene tree.

moving camera around can have extreme stuttering (fps wise)  **PARTIAL FIX** —
ChunkManager now ignores camera_moved emits inside the same chunk coord,
and chunks load with a per-frame budget (`max_loads_per_frame`) so a
boundary crossing spreads across frames. Pathfinder rebuilds are
incremental when the region didn't change, but a full rebuild still runs
on every region shift; see the "region-shift optimization" entry above.
