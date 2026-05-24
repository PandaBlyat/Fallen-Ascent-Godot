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

## Gameplay loop expansion

- [ ] **Job priorities.** Workers currently pick the Chebyshev-nearest
      unclaimed job. Designations need priorities (urgent mine vs. routine
      haul) and per-worker work types.
- [ ] **Worker needs** — power/charge, repair, "sleep" cycle. Sets up the
      AI director that CLAUDE.md flags as a future autoload candidate.
      **Implemented v1:** `_mood` stat + `_unsatisfied_needs` list on Worker;
      first need is "Needs dock room". Mood decays while needs are unmet,
      drifts back to baseline (80) otherwise. ColonyHud renders mood meter
      and an explicit "needs" line per selected worker.
- [x] **Idle behavior table.** Workers should not only poll for jobs while
      idle. Add weighted low-cost idle choices: wait, roam explored space,
      wander toward frontier cells, recharge at nearest outlet, socialize with
      another worker, and rest at a sleep fixture. Keep all path choices
      bounded and avoid per-frame scans. **Implemented v1:** bounded samples
      from explored/frontier cells plus Dock/rest/social/repair idle actions.
- [x] **Rest furniture / mental recovery.** Add a bot bed equivalent
      (working name: Stillness Cradle) as a buildable structure. Charging
      restores physical power; rest restores future mental stats.
      **Implemented v1:** renamed to Dock; rest lowers mental tiredness.
- [x] **Resource sinks and maintenance loop.** Add primitive crafting /
      service structures that consume scrap, substrate, components, circuits,
      and power cells for repairs, replacement parts, upgrades, and ongoing
      upkeep so production has pressure instead of infinite stock growth.
      **Implemented v1:** Repair Bench, Parts Loom, Maintenance Dock, and
      Calibration Shrine definitions; Parts Loom and Maintenance Dock consume
      inputs during production/upkeep, Repair Bench consumes repair materials.
- [x] **Combat + hostile entities.** Melee, knockback, stun, reactive worker
      defense, hostile spawner with cap, neutral flee+retaliate.
      **Implemented v1:** `CombatStats` Resource + `CombatService` static
      melee resolver; `HostileBot` + `HostileSpawner` (cap 12, interval ~20s,
      ≥30 tiles from origin); `LineOfSight` util shared with FogOfWar;
      neutrals raycast every 0.35–0.55s and flee; workers add `FIGHTING`
      state + `command_attack` direct order; click hostile/neutral opens
      bottom-center inspect card.
- [x] **More item kinds for real gameplay.** `Item.Kind.COMPONENT` exists
      as a placeholder alongside `SCRAP`, but nothing produces components
      yet. Mining could rarely drop one; recipes / build costs that mix
      kinds would force varied stockpiles. **Implemented v1:** substrate,
      service cores, component drops, extractor production.
- [x] **Multi-tile structures.** `BuildJob` places single walls today.
      Doors, multi-tile machines, lights, conveyors all want a different
      shape (designate footprint, multiple ingredients, blueprints).
      **Implemented v1:** wall/door/light/extractor blueprints.
- [x] **Construction blueprints / ghost preview.** A faded outline at the
      build target before completion would help readability.
- [x] **Selection box / multi-worker selection.** Currently the
      `SelectionController` picks a single worker on left-click. Drag-box
      select would let players issue group orders.
- [ ] **Direct-order queueing.** A worker issued a manual order today
      abandons it as soon as the player issues a new one. Adding a small
      queue (Shift-right-click appends) would feel more like RimWorld /
      Factorio.
- [ ] **Power-network depth.** Outlets now provide simple permanent charge
      points. Later pass should add outlet throughput, local power storage,
      damaged/disabled outlets, and player-built batteries/relays so power
      becomes a colony-planning constraint instead of free fuel.
- [x] **Production loop beyond mine/build.** Components can now drop from
      mining, but there are no recipes or machines that consume them. Add
      workbenches, repair parts, doors, lights, and upgrade costs so mining
      feeds construction choices instead of only wall spam. **Implemented v1:**
      extractor creates components; door/light/extractor consume mixed inputs.
- [ ] **AI stress/regression scenarios.** Add scripted tests for cancelling
      jobs mid-path, deleting stockpiles while workers carry items, partial
      stack hauling, and forced low-energy charging so worker state bugs do
      not regress silently.

## UI

- [x] **Replace the single debug label with a real HUD** — resource panel,
      worker/job status, current designation tool palette as actual buttons.
      **Implemented v1:** top status strip plus bottom-left grouped command
      palette.
- [x] **Designation tool palette** with on-screen buttons (today: hotkeys
      M / B / N / X / Esc only). **Implemented v1:** Orders / Zones /
      Structures tabs backed by editable UI placeholder atlas.
- [x] **Tooltip on hover** showing tile type, occupant, designation status.
- [x] **Fix item tooltip identity.** Colony tooltip should report real item
      kind for loose stacks, stored stacks, and reserved stockpile merge slots;
      avoid falling back to default `Item.Kind.SCRAP` when data is missing.
- [x] **Designator tooltips with effects and requirements.** Orders, zones,
      and structures should explain what the tool does and, for structures,
      show footprint, ingredients, build time, production, and unlock/placement
      requirements.
- [x] **Selected entity panels.** Selecting workers or built structures should
      open compact card panels. Worker cards show stats/state/current job;
      structure cards show production output, interval, current timer progress,
      blocked output state, and required inputs once crafting is added.
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
      feedback on direct orders. Partial: worker action bubble now shows
      current action above each active worker.
- [ ] **Central input / modal stack.** Esc ownership is now patched locally
      (active designation, selected worker, then settings menu), but future
      overlays/tools should go through one stack so scene-tree input order
      cannot decide which system consumes cancel.

## Tests / tooling

- [ ] **Determinism tests for procgen.** CLAUDE.md mentions these live next
      to the generator; not yet written. Bump
      `WorldGenerator.WORLDGEN_VERSION` when terrain output changes.
- [ ] **Headless smoke test** that boots `Main.tscn`, runs a fixed number of
      frames, and asserts no errors / no leaked nodes. Useful in CI.

## Rooms / Mood (v1 landed, more to do)

- [ ] **Room enclosure check.** `RoomManager.is_room_valid` currently only
      enforces a minimum cell count and the presence of a Dock (or Maint Dock)
      inside. Rimworld-style enclosure detection (walls on every external
      border, no leak to outside floor) is not implemented. Right now any
      painted floor area with a Dock counts as a valid room.
- [ ] **Multiple room kinds.** Only DOCK_ROOM exists. Future kinds:
      workshop, mess, recreation. Add to `RoomManager.Kind` and add a tab
      button per kind.
- [ ] **Per-worker assigned dock visualization.** The HUD shows "needs:
      satisfied" / "needs dock room" but doesn't draw a link from the worker
      to their owned room.
- [ ] **Dock-room rest bonus.** Resting in the assigned dock room should
      restore mental tiredness faster and trickle mood up. Today the room
      just satisfies the need; resting still uses the global nearest dock.
- [ ] **Mood breakdown thresholds.** Past behaviour like "wander off",
      "refuse jobs", "lash out" when mood < 25 is not modeled yet.

## Combat polish (v1 landed)

- [ ] **Dodge chance scaling.** All three factions ship a fixed dodge
      chance constant. Later: tie to condition, limb status, fatigue,
      assigned room (e.g. well-rested bots dodge more).
- [ ] **Damage / dodge floating text styling.** FloatingText is monochrome
      labels per hit. Add crit/heal variants when added; consider object
      pooling once a fight involves more than ~20 hits/sec.

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
- [ ] **Display-mode edge cases on Linux/Wayland / multi-monitor setups.**
      SettingsManager now has explicit Windowed, Borderless, and Fullscreen
      paths, but platform window managers can still differ. Revisit with
      platform-specific reports.

moving camera around can have extreme stuttering (fps wise)  **PARTIAL FIX** —
ChunkManager now ignores camera_moved emits inside the same chunk coord,
and chunks load with a per-frame budget (`max_loads_per_frame`) so a
boundary crossing spreads across frames. Pathfinder rebuilds are
incremental when the region didn't change, but a full rebuild still runs
on every region shift; see the "region-shift optimization" entry above.

Update: current prototype now uses a finite preloaded colony map, so camera
movement no longer generates chunks or shifts Pathfinder's region. If map
sizes grow much bigger, revisit async loading screen / chunked pathfinding
instead of returning to camera-driven infinite streaming.
