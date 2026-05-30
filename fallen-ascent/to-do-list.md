# Fallen Ascent — To-Do List

Running ledger of work that is **known to be needed** but is intentionally
out of scope for the current task. New entries get added here whenever an
agent identifies a gap that future work must close. Remove an entry only
when it's actually done.

Format: `[area] short description — why it matters / first hint at how`.

---



## Embark + achievements + lighting + highlighter session

- [x] **Embark screen worker data wired to gameplay.** Done: `EmbarkScreen`
      emits `Array[WorkerLoadout]` → `GameState.embark_loadouts` →
      `WorkerSpawner.spawn` → `Worker.apply_loadout`. Names come from
      `WorkerSpawner.BOT_NAMES`, personalities from `Worker.Personality`.
- [x] **Embark depth: parts, skills, personalities, AP economy.** Done:
      `PartDatabase` (Cogmind-style T1–T5 parts), `WorkerLoadout` (parts +
      skills + specialty), achievement-point store for tier/worker unlocks.
- [ ] **Achievement hooks for non-signal events.** `AchievementManager` has
      public methods (`on_stockpile_designated`, `on_room_designated`,
      `on_workshop_placed`, `on_worker_saved`, `on_worker_count_changed`) but
      they aren't yet called from `StockpileManager`, `RoomManager`,
      `StructureManager`, or `SelectionController`. Wire them in to unlock
      those achievements. (`on_worker_count_changed` also needs a caller when
      workers spawn/die so the 5/10-worker achievements can fire.)
- [ ] **Part placeholder art + worker visuals.** Parts currently have no atlas
      art and `Worker` still draws a generic body regardless of equipped parts.
      Add per-part placeholder icons (an embark part atlas) and reflect a few
      parts on the worker sprite (legs/weapon) once art lands. Achievement
      icons are flat-color placeholders in `resources/ui/achievements_atlas.png`.
- [x] **Wire WorkerLines flavour to actions.** `WorkerLines.get_line()` is
      now called on state transitions (`_try_say_personality_line`) and for
      guaranteed low-energy/low-condition alerts (`_say_line`). Speech appears
      in a purple-tinted bubble above the action text, fades in/out over 4.5s.
- [ ] **Balance pass on shell baseline vs part tiers.** `PartDatabase.SHELL`
      and the tier mod values are first-draft. Once playable, tune so a Tier-1
      full kit ≈ the old fixed worker and higher tiers feel worth the AP.
- [ ] **Lighting shader pixel_size tuning.** `pixel_size = 4.0` gives chunky
      4×4 dither blocks. Tune together with `dither_strength` and `light_bands`
      once real pixel-art tile art lands — values might need adjusting for
      smaller tiles.

## Embark + worker-panel polish session

- [ ] **Unify in-game HUD buttons with the worker-card button theme.** Main menu,
      settings, and embark now skin buttons with `worker_card.png` via
      `UiStyle.button_theme()`. The in-game `ColonyHud` buttons still use the
      code-built flat `_button_style`. Consider routing them through the same
      shared theme (or `UiStyle`) so the whole game's buttons match.
- [ ] **Weight randomized part loadouts toward the chosen role.**
      `EmbarkScreen._randomize_parts` picks affordable parts uniformly at random.
      It could bias toward the worker's role (e.g. a Miner favours drill arms) so
      "Randomize" produces coherent builds, not just legal ones.
- [ ] **Per-part placeholder icons in the embark picker + panel.** Parts still
      have no atlas art (see the older note below). The new per-part condition
      bars and slot buttons would read better with icons.

## Save/load + highlighter + AI fixes (this session)

- [ ] **Save system fidelity gaps.** `SaveManager` (autoload) +
      per-system `capture_save`/`restore_save` snapshot a full colony, but
      some state is intentionally dropped on load and may want restoring
      later: in-flight worker jobs/paths/combat targets (bots reload IDLE;
      carried stacks re-drop as loose items), build/craft/operate progress
      (jobs come back fresh), pending haul jobs (regenerate from restored
      items+stockpiles), door/delete-overlay/structure timers beyond the
      raw `timer`, and HostileSpawner wave cadence (live hostiles restored
      by pos+hp). `SaveManager.SAVE_VERSION` is written but not validated —
      add migration when the schema changes. Diff replay assumes
      `preload_entire_map` (all chunks loaded); streaming maps would need
      lazy per-chunk diff application.
## Worker dialogue + achievement toasts + movement fixes session

- [x] **Achievement modal redesign.** `AchievementToast` now shows a centered
      full-screen modal (scale-in + gold border pulse) that pauses the game and
      queues multiple unlocks. AP awarded is shown prominently. Click or wait 4.5s
      to dismiss.
- [x] **Worker speech cooldown.** `SPEECH_CHANCE` reduced 0.22→0.10 and a
      50-second per-worker cooldown added (`_speech_cooldown`) so dialogue lines
      fire at most once every ~50 game-seconds.
- [x] **Smooth lighting transitions.** Lighting shader now blends `prev_light_mask`
      → `light_mask` via `transition_t` over 0.35 s. `LightingOverlay` captures a
      snapshot before each update and animates the blend with a Tween.
- [x] **Save list panel.** "Load Save" opens a scrollable panel listing all
      `user://save_*.sav` files with date, size, Resume and two-click Delete.
      `SaveManager` now supports multi-slot paths (`save_0.sav` … `save_4.sav`)
      with `list_saves()` and `delete_save()`.
- [x] **Haul job priority fix.** `JobBoard._priority_of` changed so MineJob=15
      and HaulJob=40, making mine/build/operate rank above hauling. Workers no
      longer abandon nearby mine tasks to haul items.

- [ ] **Speech bubble max-width / font tuning.** The personality speech bubble
      truncates at 48 chars but Orbitron is wide — at zoom-out some text may
      still be too wide. Consider switching to a narrower font or adding a
      draw_string `width` clip. Tune `SPEECH_FONT_SIZE` and `SPEECH_CHANCE`
      during playtest.
- [ ] **Achievement toast sound effect.** `AchievementToast` shows a visual modal
      but plays no sound. Add a short chime via `AudioManager` once a suitable
      SFX asset exists.
- [ ] **Worker name / action bubble GPU batching.** Each worker calls
      `queue_redraw()` every frame during movement (fixed for smooth scaling).
      For 100+ workers this adds draw-call overhead. Profile and consider a
      single `CanvasItem` overlay that draws all name bubbles in one pass.
- [ ] **Save slot UI in settings.** SettingsMenu's Save button still always
      writes to `save_0.sav`. Add a slot picker so the player can save to
      different slots without overwriting the auto-save.

- [ ] **Spatial nearest-job index for huge designations.**
      `JobBoard.claim_next_for` now blocks unreachable jobs board-wide on a
      failed path (`Worker._mark_job_failed` → `Job.block_briefly`), caps
      per-tick claim attempts, and the global fallback scans only the
      nearest non-empty chunk cluster instead of every job. This is a big
      win but still O(jobs nearby); a per-chunk "closest claimable job"
      cache would scale further for thousand-tile mining orders.

## Move / dismantle / debris / floor / forbid / ore-cluster session

- [x] **Move button for placed structures.** Workshop/object info panel now has
      a "Move" button. Clicking it enters `RELOCATE` designator mode; the player
      picks a new tile; old structure removed instantly (no refund), new
      `BuildJob` queued at 50% pre-filled ingredients.
- [x] **Workshop dismantling as worker job.** Deleting a structure queues a
      `DismantleJob` (toggle second click to cancel). Worker walks to the
      structure and works for 4 s, then calls `complete_dismantle_at` which
      removes it and refunds 50% ingredients.
- [x] **Debris tile + two new techs.** `TILE_DEBRIS` already in TerrainGenerator;
      `TechDatabase.DEBRIS_CLEARANCE` (unlocks mining debris) and
      `TechDatabase.BASIC_FLOORING` (unlocks building floor tiles) added.
      `can_place_blueprint` gates WALL-on-debris behind DEBRIS_CLEARANCE.
- [x] **Ore wall clusters.** `_service_core_pass` now expands each RICH_WALL
      seed into a cluster of 3–4 adjacent TILE_WALL cells using seeded RNG.
- [x] **Forbidden zone painting.** `ForbiddenZoneManager` Node2D tracks
      player-painted forbidden cells with a red overlay. Workers skip forbidden
      cells for idle wander. "Forbid" / "Unforbid" paintbrush buttons in Zones
      tab. Save/restore included.
- [x] **Fix workers stuck inside workstations.** `_build_stand_for` finds a
      walkable neighbor cell that is NOT inside the structure's footprint.
- [x] **Manual order idle time.** After completing a job from
      `_direct_order_queue`, workers idle 2–3 s before picking the next
      automatic job.
- [x] **Mine unexplored tiles.** Players can designate any tile for mining
      (fog-of-war included). `_begin_mine` routes through unexplored space when
      needed. `_complete_mine` cancels silently if tile turns out not minable.
- [ ] **Cradle-spawned workers and forbidden zones (idle wander only).** Workers
      spawned by the Replication Cradle receive `null` for
      `_forbidden_zone_manager` and won't avoid forbidden cells when picking idle
      *wander* targets. (Forbidden *jobs* are now handled centrally in
      `JobBoard._job_is_claimable`, so all workers — cradle-spawned included —
      already skip claiming jobs in forbidden cells.) Fix wander by adding a
      `_forbidden_zone_manager` field to `StructureManager` and passing it
      through `WorkerSpawner.spawn_one_at`.

## Bug-fix pass: forbidden jobs / manual idle / relocate ghost

- [x] **Forbidden zones now block jobs, not just wander.** `JobBoard` holds an
      optional `ForbiddenZoneManager` (`set_forbidden_zone_manager`, wired in
      `ColonySite._ready`). `_job_is_claimable` rejects any auto-claimed job whose
      work cell (or any BuildJob footprint cell) is forbidden. Manual orders
      bypass this (they go through `command_*`, never `claim_next_for`).
- [x] **Manual-order idle grace actually fires + scales with game speed.** The
      grace window was only set when an order came off `_direct_order_queue`, so
      single (non-shift) orders and manual *moves* (which bypassed `_finish_job`)
      never got it. Now every `command_*` with `clear_queue=true` sets
      `_last_job_was_manual`, the MOVING_FREEFORM completion routes through the
      shared `_apply_post_job_idle()`, and the 2–3 s window is multiplied by
      `GameState.game_speed` so the real-time pause stays constant at 2x/3x
      (idle counts down in `Engine.time_scale`-scaled delta).
- [x] **Relocate has a build-style placement ghost.** `RELOCATE` mode now draws
      the footprint ghost (valid/invalid tint) via the generalized
      `_draw_build_ghost(id, anchor, rotation)` and supports `R` to rotate
      (`_relocate_source_rotation`) before committing.
- [ ] **(Nicety) Abandon in-flight jobs when a cell becomes forbidden.** Marking
      a cell forbidden only stops *future* claims; a worker already mid-job there
      finishes it. Acceptable for now (RimWorld-like), but `ForbiddenZoneManager.
      mark()` could notify `JobBoard`/workers to release claims in newly-forbidden
      cells for snappier feedback.

## Big features still owed (from the move/dismantle/forbid request)

- [ ] **World-gen easter eggs / unique rooms behind ore walls + more floor/wall
      variety.** Sealed vaults with loot, themed rooms, using the floor shader
      for variety. Code-only procgen work in `TerrainGenerator` / service-core
      pass; bump `WORLDGEN_VERSION`.
## Mood/friction + object condition session

- [x] **Friction / mood-spiral / death-spiral + mental breaks.** Mood is now
      needs-driven (`_update_mood` drifts toward a needs-lowered setpoint). Below
      `MOOD_BREAK_THRESHOLD` `_break_risk` builds and snaps the bot into a
      `MentalBreaks.Type` break: Drift, Lockup, Fixation, Wall-In (major),
      Berserk (major). Breaks have banded durations + catharsis recovery and
      drain nearby bots' mood on trigger (`_spread_break_contagion`) — the
      spiral. Personality-weighted pick. Saved/restored. Shown in the worker
      stat panel. Expanded needs: Power-starved, Exhausted, Lonely, Damaged
      chassis, Standing in filth.
- [x] **Condition 0–100 on every placed object + breakdowns + repair jobs.**
      `StructureManager` tracks per-structure `condition` (saved/restored, in the
      info card). Machines wear over time + per operation; broken machines stop
      working; berserk bots smash structures (`damage_structure_at`). Below
      `STRUCTURE_REPAIR_THRESHOLD` a high-priority `RepairStructureJob` auto-queues
      and a worker repairs it to full (`State.FIXING_STRUCTURE` →
      `repair_structure_at`).
- [ ] **Mood/condition balance + polish pass (needs playtest).** First-draft
      tuning for: break thresholds/durations/contagion, ambient wear rate,
      repair duration, mood setpoint drops. Also: Wall-In can fully box a bot in
      (it can then run out of power and go downed needing rescue) — intended
      drama but verify it isn't a soft-lock at scale. Consider an alert/toast on
      mental break (EventBus.worker_mental_break is emitted but unhandled), an SFX,
      and a persistent in-world visual tint for broken bots (only a 4.5s bubble +
      stat-panel banner today). Repair is currently free (time only) — consider a
      small material cost once the economy can support it without deadlocks.
- [ ] **More strange-mood variety.** Five breaks today. The theme supports more
      (e.g. hoarding a specific item, obsessive crafting of one object, broadcast
      static that worsens contagion, self-mining). Extend `MentalBreaks.Type` +
      `Worker._decide_break_behavior`.

## Big features still owed (from the move/dismantle/forbid request)

- [x] **World-gen easter eggs / unique rooms behind ore walls + more floor/wall
      variety.** Done: hidden sealed chambers (8 themed types: resource cache,
      ancient chamber, hazard room, treasure vault, abandoned workshop, ancient
      terminal, crystal grotto, forgotten generator) placed behind mineable walls
      via `_hidden_room_pass()`. Floor shader now uses per-chunk biome-aware
      uniforms via `_apply_zone_shader_uniforms()` in `Chunk.gd`
      (The Abyss=corroded, Industrial=hazard/LEDs, Habitation=clean,
      Lithic=cracked, Structural=conduit/grate). World detail pass adds corridor
      trim, dead-end furnishings, pillar variety, environmental storytelling,
      and void-edge safety railings. `WORLDGEN_VERSION` bumped to 10.
- [ ] **FLOOR tile requires BASIC_FLOORING tech at build time.** The tech gate
      in `ColonyHud` greys the button out, but `can_place_blueprint` and
      `Worker._complete_build` do not check the tech. Add a
      `TechManager.is_unlocked(TechDatabase.BASIC_FLOORING)` guard in both
      so cheats / console-placed floors are also gated.

## Degradation + achievement + worldgen session

- [x] **Achievement bug: hostile achievements firing prematurely.**
      Done: `combatant_died` signal now carries `attacker: Node` parameter.
      `first_hostile_killed` only unlocks when a sane (non-berserk) worker
      lands the killing blow. Environmental kills (acid) and berserk-worker
      kills no longer trigger the achievement.
- [x] **Stockpile degradation when not enclosed.**
      Done: items in stockpiles not enclosed by walls + door degrade via
      condition decay (100 → 0 per stack, consuming 1 count per cycle).
      `StockpileZone.is_enclosed()` checks perimeter for walls/doors.
      `StockpileManager._process()` ticks every 10s game-time. UI shows
      warning in tooltip and stockpile card. Condition persisted in saves.
- [ ] **Stockpile degradation balance.** The current `DEGRADE_AMOUNT_PER_TICK`
      (5.0 per 10s) and `DEGRADE_INTERVAL_SECONDS` (10s) are first-pass values.
      Playtest and tune so exposed stockpiles feel urgent but not punishing.
      Consider making degradation rate scale with item rarity.
- [ ] **Per-chunk floor material overhead.** Each chunk now creates its own
      `ShaderMaterial` instance for biome uniforms. For a 12×12 map this is
      144 materials (lightweight), but measure draw-call impact if chunk count
      grows. If needed, batch by zone (group chunks sharing the same zone into
      a shared material pool).

## Worldgen expansion + pixel simulation overhaul session

- [x] **Void tile bug fix.** `floor_variation.gdshader` now skips all effects
      for near-black pixels (luminance < 0.08), preventing floor shader from
      drawing brightness/tint/wear on void tiles.
- [x] **New room styles (5).** Vertical Shaft (void column + conduit platforms),
      Flooded Chamber (fluid + raised walkways), Crypt (service core sarcophagi),
      Armory (rich-wall weapon racks), Hexagonal Chamber (hex-distance carving).
      All wired into `_pick_room_style` with zone-appropriate weighting.
- [x] **Corridor improvement pass.** `_corridor_improvement_pass` adds periodic
      outlet lights along corridors and carves small rest alcoves (2×2 widenings
      with outlets) into wall-adjacent corridor tiles.
- [x] **Expanded hidden rooms.** 3 new themes: Ancient Terminal (teleporter +
      conduit ring + service cores), Crystal Grotto (irregular rich-wall clusters),
      Forgotten Generator (dense service core + outlet ring on conduit floor).
- [x] **Improved macro structures.** 2 new macro styles: Grand Atrium
      (concentric material rings with outlet ring) and Reactor Core (central void
      with radiating conduit arms + service core tips). Existing styles enhanced
      with rich-wall accents, conduit rings, and service core markers.
- [x] **Pixel simulation shader overhaul.** Complete rewrite of
      `pixel_simulation.gdshader` with multi-layer procedural megastructure:
      distant structural beams, mid-ground pipe networks, vertical spires with
      blinking antenna lights, ambient deep glow sources, falling debris particles,
      rising embers, and improved CRT post-processing. Background now has real
      depth instead of flat wallpaper. GDScript timing tuned: snappier rise/decay,
      longer hold for readability, higher background dimness for contrast.
- [ ] **Hidden room cross-chunk continuity.** Hidden rooms currently only exist
      within a single chunk. For truly grand hidden chambers, a cross-chunk
      coordination pass could place rooms that span chunk boundaries. Requires
      `WorldGenerator` to pre-plan hidden room locations at the overview level.
- [ ] **More corridor variety.** Current corridors are still mostly L/T shaped.
      Consider adding winding/diagonal corridor styles, stairway segments
      (conduit ramps), and corridor junctions with wider intersections.
