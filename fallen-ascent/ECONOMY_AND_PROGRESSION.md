# Economy, Tech Tree, and Progression

Snapshot of current prototype state. This is not a fantasy design doc. It is
what the game actually does right now: salvage, refine, service bots, spend
wisdom, then turn enough parts into another bot.

## Current Loop

Current economy has 5 layers:

1. **Mine and salvage.** Walls, service cores, rich walls, and mineable props
   feed raw parts into colony.
2. **Process.** Extractor, Fabricator, and Assembly Press turn salvage into
   better parts, datacores, and charge cells.
3. **Support colony.** Docks, repair, lights, sensors, storage, and outlets
   keep bots working longer.
4. **Research.** Meditation turns idle time into Wisdom.
5. **Expand population.** Replication Cradle consumes high-tier parts and
   creates another worker.

This is not trade economy, food economy, or market economy. It is salvage
throughput plus colony maintenance.

## Resource Ledger

| Resource | How to get it | Main use |
| --- | --- | --- |
| Wisdom | Bot meditates at Meditation Pad; Focused Mind raises rate by 25% | Unlock techs |
| Scrap | Mine walls, service cores, rich walls, static props, or craft outputs from some prop salvage | Baseline build and craft fuel |
| Plating | Mine walls, service cores, rich walls, static props, or run Extractor | Mid-tier construction and crafting |
| Mechanism | Mine service cores, rich walls, props, or run Extractor / Assembly Press / some prop salvage | Machines, sensors, lights, service gear |
| Datacore | Mine service cores, rich walls, props, or run Fabricator / some prop salvage | Sensors, research-adjacent gear, advanced crafting |
| Charge cell | Mine service cores, props, or run Fabricator / Assembly Press / some prop salvage | Power-adjacent items, late service structures |
| Storage bin item | Craft at Fabrication Spot, then place on stockpile tile | Raises storage capacity |
| Outlet extension item | Craft at Fabrication Spot, then place on outlet tile | Lets 2 workers recharge from one outlet |
| Rudimentary sensor item | Craft at Fabrication Spot, then place on floor | Short-range reveal source |
| Small light device item | Craft at Fabrication Spot, then place on floor | Small work light |
| Large light device item | Craft at Fabrication Spot, then place on floor | Large work light |

Wisdom is abstract. Not an item. Not hauled. Not stored as physical stock.

## Terrain And Salvage Sources

| Source | Yields | Notes |
| --- | --- | --- |
| Wall | Scrap, plating, rare mechanism | Main early mining target |
| Service core | Wall loot plus extra plating, mechanism, datacore, charge cell | Best all-round mine target |
| Rich wall | Wall loot plus extra plating and datacore | Better than wall, worse than service core |
| Rust | No item yield | Scrape to floor only |
| Teleporter, water, conduit, debris, floor | No direct loot | Map features only, not economy nodes |

### Mineable Static Props

Static props are deterministic salvage nodes. They matter because they are the
cleanest source of mid-tier parts.

| Prop | Main drops |
| --- | --- |
| Rusty storage bin | 2-4 scrap, 1-2 plating at 55%, 1 mechanism at 18% |
| Rusty broken grille | 1-2 scrap, 1 plating at 45% |
| Rusty fan | 1-2 scrap, 1 mechanism at 32%, 1 plating at 25% |
| Pile of scrap | 2-5 scrap, 1 plating at 28% |
| Broken thermometor box | 1 scrap, 1 mechanism at 24%, 1 datacore at 10% |
| Broken vent | 1-2 scrap, 1 plating at 36% |
| Pile of rusty girdle | 1-3 scrap, 1-2 plating at 72% |
| 2nd pile of rusty girdle | 1-2 scrap, 1-2 plating at 68% |
| Pile of components | 1-2 scrap, 1-2 mechanism at 78%, 1 datacore at 12% |
| Broken batteries | 1-2 scrap, 1 charge cell at 42%, 1 mechanism at 18% |
| Pile of batteries | 1-2 scrap, 1-2 charge cell at 72% |
| Storage tank | 2-3 scrap, 1-2 plating at 75%, 1 charge cell at 12% |
| Satellite dish | 1-2 scrap, 1-2 mechanism at 58%, 1 datacore at 28% |

## Structure And Object Economy

There are two build paths:

1. **Direct structures.** Spend raw materials at build site, structure appears.
2. **Crafted objects.** First craft object item at Fabrication Spot, then place
   that item as a structure from Objects tab.

That split matters. It is the main reason this economy feels like colony sim
instead of simple placement game.

### Direct Structures

| Structure | Cost | Size | Build time | Placement | Role | Unlock |
| --- | --- | --- | --- | --- | --- | --- |
| Wall | 1 scrap | 1x1 | 2.0s | Floor only | Turns tile into wall | Awakening |
| Door | 1 scrap, 1 mechanism | 1x1 | 2.5s | Walkable floor | Controlled barrier | Awakening |
| Light | 1 mechanism | 1x1 | 2.5s | Walkable floor, within 15 tiles of outlet | Basic work light | Awakening |
| Charge Pad | 1 scrap, 1 mechanism, 1 charge cell | 1x1 | 2.5s | Walkable explored floor | Converts floor into outlet | Power I |
| Extractor | 2 scrap, 2 plating, 1 mechanism | 2x2 | 4.0s | Machine Room, one footprint cell on outlet | Worker job, no inputs, outputs plating / mechanism | Refining I |
| Sensor | 1 mechanism, 1 datacore | 1x1 | 2.5s | One footprint cell on outlet | Long-range reveal source | Sensors I |
| Fabricator | 2 scrap, 1 plating, 1 datacore | 2x1 | 3.5s | Machine Room, one footprint cell on outlet | Worker job, no inputs, outputs datacore / charge cell | Power II |
| Dock | 1 scrap, 1 plating | 2x1 | 3.0s | Walkable explored floor | Rest node | Awakening |
| Repair Bench | 2 scrap, 1 mechanism | 2x1 | 3.0s | Walkable explored floor | Repairs bot condition, spends scrap first, then mechanism | Awakening |
| Assembly Press | 2 plating, 1 datacore | 2x1 | 3.0s | Machine Room | Worker job, consumes plating + datacore, outputs mechanism / charge cell | Refining II |
| Mechanic Dock | 3 scrap, 2 mechanism, 1 charge cell | 2x2 | 4.5s | One footprint cell on outlet | Anchors Mechanic Room, heals limbs of workers inside | Mechanic Dock |
| Calibration Shrine | 1 datacore, 1 charge cell | 2x1 | 3.0s | One footprint cell on outlet | Future mental / social recovery hook | Calibration |
| Meditation Pad | 2 scrap, 1 plating | 2x1 | 3.0s | One footprint cell on outlet | Wisdom source | Awakening |
| Replication Cradle | 8 scrap, 6 plating, 4 mechanism, 2 datacore | 2x2 | 8.0s | Machine Room, one footprint cell on outlet | Worker job, consumes 20 scrap, 10 plating, 8 mechanism, 4 datacore, 2 charge cell over 120s to spawn new bot | Replication Cradle |
| Fabrication Spot | 1 scrap, 1 plating | 1x1 | 1.5s | Walkable explored floor, outside stockpiles | Local craft station for placeable objects | Awakening |

### Crafted Placeable Objects

These are made at Fabrication Spot first. Then the resulting object item is
placed as a build job.

| Object item | Craft recipe | Craft time | Placement | Role | Unlock |
| --- | --- | --- | --- | --- | --- |
| Storage bin | 2 scrap, 1 plating | 5.0s | On stockpile tile | Raises cell capacity from 4 to 12 | Awakening |
| Outlet extension | 1 mechanism, 1 charge cell | 6.0s | On outlet tile | Lets two workers recharge from one outlet | Awakening |
| Rudimentary sensor | 1 mechanism, 1 datacore | 7.0s | On walkable floor | Short-range reveal source | Awakening |
| Small light device | 1 scrap, 1 mechanism | 4.0s | On walkable floor | Small work light, 4 tile radius | Awakening |
| Large light device | 2 plating, 1 mechanism, 1 charge cell | 8.0s | On walkable floor | Large work light, 8 tile radius | Awakening |

## Tech Tree

Current tree is broad, not deep. One free root, 5 branches, 2 deferred tier-3
placeholders, 1 capstone.

```text
Awakening
|- Power I -> Power II -> Power III (deferred)
|- Refining I -> Refining II -> Refining III (deferred)
|- Sensors I
|- Focused Mind -> Calibration
|- Mechanic Dock -> Mechanic Room
`- Replication Cradle (requires Power II + Refining II + Mechanic Dock)
```

| Tech | Wisdom cost | Prereq | Unlocks | Current read |
| --- | --- | --- | --- | --- |
| Awakening | 0 | none | Wall, Door, Light, Dock, Repair Bench, Meditation Pad, Fabrication Spot, Storage Bin, Outlet Extension, Rudimentary Sensor, Small Light Device, Large Light Device | Free starter layer |
| Power I | 40 | Awakening | Charge Pad | First outlet expansion |
| Power II | 90 | Power I | Fabricator | Mid-game power/process pivot |
| Power III | 180 | Power II | nothing yet | Placeholder |
| Refining I | 60 | Awakening | Extractor | First salvage machine |
| Refining II | 120 | Refining I | Assembly Press | Real conversion step |
| Refining III | 220 | Refining II | nothing yet | Placeholder |
| Sensors I | 50 | Awakening | Sensor | Basic map reveal |
| Focused Mind | 80 | Awakening | no build unlock | Meditation 25% faster |
| Calibration | 160 | Focused Mind | Calibration Shrine | Future mental / social support |
| Mechanic Dock | 100 | Awakening | Mechanic Dock | Service branch starter |
| Mechanic Room | 180 | Mechanic Dock | no build unlock | Room unlock for limb repair service |
| Replication Cradle | 400 | Refining II, Power II, Mechanic Dock | Replication Cradle | Late-game population growth capstone |

## What A Colony Sim Player Reads Here

From RimWorld / Dwarf Fortress angle, this economy says:

- Early game is not about food. It is about **access**: power, rest, repair,
  storage, light, and a place to turn scrap into parts.
- Mid game is about **throughput**: extractor, fabricator, assembly press,
  better sensing, and room control.
- Late game is about **replication**: enough wisdom and parts to make another
  worker.
- Service structures carry a lot of weight. This is a robot colony, so colony
  health is energy, condition, limb repair, and mental tiredness, not hunger.

## Meta-Progression: Achievements, Embark, and Worker Builds

This layer sits *outside* a single colony. It is how the player's account grows
across playthroughs and how each new colony's starting crew is assembled.

### Achievement points (AP)

`AchievementManager` (autoload) persists unlocked achievements **and** an AP
wallet to `user://achievements.cfg`. Each achievement grants a fixed point
value (5–40); the registry is `AchievementManager.ACHIEVEMENTS`. AP is a
**persistent currency** spent — permanently — on the embark screen:

| Sink | Cost (AP) | Effect |
| --- | --- | --- |
| Unlock Tier 2 / 3 / 4 / 5 | 10 / 25 / 50 / 90 | Makes that part tier buyable in embark (still costs pool points to equip) |
| Add worker slot (×3) | 15 / 30 / 50 | One more starting worker (base 3 → max 6) |

`available_points = total_earned − spent`. A brand-new account has 0 AP, so it
can only field 3 workers with Tier-1 parts; AP earned from achievements unlocks
deeper builds and bigger crews over time. The Achievements menu shows each
entry's icon (placeholder atlas `resources/ui/achievements_atlas.png`), point
value, and the running wallet.

### Embark: pool points + Cogmind-style parts

The embark screen is the per-run loadout shop. It draws worker **names** from
`WorkerSpawner.BOT_NAMES` and **personalities** from `Worker.Personality` — the
same systems gameplay uses, so there is no separate "embark identity" anymore.

Each worker is a **shell**: a slow walking chassis with low bash, tiny carry,
and a thin battery (`PartDatabase.SHELL`). Parts slot into five categories
(Power, Propulsion, Manipulation, Utility, Weapon; `PartDatabase.SLOT_LAYOUT`
exposes 1/2/2/2/1 slots) to build it up. Parts span Tiers 1–5; only tiers the
account has unlocked appear. Equipping spends from a per-embark **pool**
(`POOL_PER_WORKER × crew size`, currently 12 each), forcing trade-offs between
"everyone gets a basic kit" and "one elite specialist."

Stat keys parts contribute (see `PartDatabase`): `move_speed`, `work_speed`,
`mine_speed`, `build_speed`, `carry`, `max_hp`, `armor`, `bash_min/max`,
`sight`, `energy_recharge`, `energy_drain`, `wisdom`, `dodge`, `mood`.

### Worker skills and personalities now matter

- **Skills** (`WorkerLoadout.SKILL_KEYS`): Mining, Construction, Hauling,
  Combat, Research. Levels 0–5 sharpen the matching work rate / carry / bash /
  wisdom. The embark **specialty** dropdown (Generalist, Miner, Builder, Hauler,
  Guard, Researcher) seeds a skill spread.
- **Personalities** previously only flavoured dialogue. They now apply real
  modifiers (`WorkerLoadout.PERSONALITY_MODS`): e.g. Grumpy hits harder but is
  perpetually low-mood, Cheerful has a high resilient mood, Philosophical
  researches fast but works slowly, Competitive is fast but power-hungry. The
  enum was expanded from 6 to 9 (adding Nostalgic, Competitive, Glitchy) to
  match the dialogue buckets `WorkerLines` already shipped.

### How it flows together

`WorkerLoadout.derive()` folds parts + skills + personality into one flat stats
dict. `Worker.apply_loadout()` pushes it onto a live worker (move speed, work
rates, carry, HP, bash, armor, sight, energy economy, mood baseline/recovery).
The embark screen emits an `Array[WorkerLoadout]`; `GameState.embark_loadouts`
carries it to `ColonySite`, which hands it to `WorkerSpawner.spawn` (one worker
per loadout). Workers spawned **without** a loadout (Replication Cradle, legacy
saves) keep the original pre-parts balance, so nothing regresses. Loadouts are
saved/restored per worker, so a customized crew survives reload.

## Naming And Logic Notes

These are player-facing observations, not code changes.

- `Parts Loom` is already better as `Assembly Press`. Keep that line.
- `Mechanic Dock`, `Maintenance Dock`, and `Dock Room` are too close. Pick one
  family and stick to it. `Service Dock` or `Maintenance Bay` would read
  cleaner.
- `Dock Room` does not instantly read like a sleeping or rest space. A colony
  sim player will probably understand `Dormitory`, `Rest Quarters`, or `Bunk
  Room` faster.
- `Calibration Shrine` feels mystical against rest of industrial language. If
  tone is meant to stay hard industrial, `Calibration Bench` or `Tuning Station`
  reads clearer.
- `Rudimentary Sensor`, `Outlet Extension`, `Small Light Device`, and `Large
  Light Device` are mechanically clear but bland. `Sensor Mast`, `Power
  Splitter`, `Work Light`, and `Floodlight` would land faster.
- `Replication Cradle` reads like birth, not smelting. Output is a worker, so `Replication
  Cradle`, `Assembly Cradle`, or `Birth Cradle` would read more honest.
- `Broken thermometor box` has a typo in prop naming. If this is meant to ship,
  it should be `thermometer`.
- `Power III` and `Refining III` are pure placeholders. That is fine for now,
  but they are dead nodes in current tree and should be called out as such in
  UI or removed until they do something.

## Current Gaps

- Meditation Chamber exists as room type, but current code does not wire a
  distinct meditation-room bonus into Wisdom gain yet.
- Power network is still outlet-based, not a real energy distribution system.
- No trade, food, or market loop yet.
- No save layer yet for wisdom or unlocked techs.
