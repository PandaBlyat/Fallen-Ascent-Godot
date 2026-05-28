# Fallen Ascent — To-Do List

Running ledger of work that is **known to be needed** but is intentionally
out of scope for the current task. New entries get added here whenever an
agent identifies a gap that future work must close. Remove an entry only
when it's actually done.

Format: `[area] short description — why it matters / first hint at how`.

---



## Embark + achievements + lighting + highlighter session

- [ ] **Embark screen worker data not wired to gameplay.** `EmbarkScreen.gd`
      generates name/role/trait for each starting worker and emits them via
      `embark_confirmed`. Currently the data is discarded — wire it into
      `WorkerSpawner` so workers start with the chosen names and traits once
      Worker has a `display_name` setter and trait system.
- [ ] **Achievement hooks for non-signal events.** `AchievementManager` has
      public methods (`on_stockpile_designated`, `on_room_designated`,
      `on_workshop_placed`, `on_worker_saved`, `on_worker_count_changed`) but
      they aren't yet called from `StockpileManager`, `RoomManager`,
      `StructureManager`, or `SelectionController`. Wire them in to unlock
      those achievements.
- [ ] **Embark screen: future depth.** Limb selection, skill points,
      personality buffs/debuffs, and achievement-point-based extra workers
      are all stubbed. Add once the Worker trait system exists.
- [ ] **Lighting shader pixel_size tuning.** `pixel_size = 4.0` gives chunky
      4×4 dither blocks. Tune together with `dither_strength` and `light_bands`
      once real pixel-art tile art lands — values might need adjusting for
      smaller tiles.

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
- [ ] **Spatial nearest-job index for huge designations.**
      `JobBoard.claim_next_for` now blocks unreachable jobs board-wide on a
      failed path (`Worker._mark_job_failed` → `Job.block_briefly`), caps
      per-tick claim attempts, and the global fallback scans only the
      nearest non-empty chunk cluster instead of every job. This is a big
      win but still O(jobs nearby); a per-chunk "closest claimable job"
      cache would scale further for thousand-tile mining orders.
