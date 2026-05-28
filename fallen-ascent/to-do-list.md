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
