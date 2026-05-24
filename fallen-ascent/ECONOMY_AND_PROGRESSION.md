# Economy And Progression

Snapshot of current prototype economy, current progression tree, known clarity problems, and proposed direction for a stronger droid/sentient-AI colony economy.

## Current Economy

### Storage

- Items exist as loose stacks or stockpile stacks.
- One stockpile tile stores one item stack.
- Current intended tile capacity: 16 items per tile.
- Total stockpile capacity is `stockpile tile count * 16`.
- HUD resource counts combine loose items plus all stored stockpile stacks.

### Current Resources

| Resource | Main Sources | Main Uses | Current Role |
| --- | --- | --- | --- |
| scrap | Any mined wall, service core, rich wall | Walls, doors, extractors, charge pads, fabricators, docks, repair benches, maintenance docks, bot repair | Basic material and repair feedstock |
| substrate | Random mining drop, service cores, rich walls, extractor | Extractor, fabricator, dock, parts loom | Structural feedstock |
| component | Rare mining drop, service cores, extractor, parts loom | Door, light, extractor, sensor, charge pad, repair bench, maintenance dock, fallback repair | Mid-tier machine part |
| circuit | Service core, rich wall, fabricator | Sensor, fabricator, parts loom, calibration shrine | Advanced logic material |
| power cell | Service core, fabricator, parts loom | Charge pad, maintenance dock, calibration shrine | Portable stored power |

### Current Terrain And Resource Nodes

| Tile | Gameplay Role |
| --- | --- |
| floor | Walkable base tile |
| wall | Mineable; always drops scrap |
| rich wall | Mineable; drops scrap, substrate, chance of circuit |
| service core | Mineable; drops scrap, substrate, chance of component, circuit, power cell |
| outlet | Charges bots and powers some structures by placement adjacency/footprint |
| conduit floor | Walkable flavor tile |
| rust sludge | Scrape target; clears to floor |
| void | Non-walkable blocker |
| teleporter | Placeholder/rare tile, no full economy role yet |

### Current Structures

| Structure | Cost | Production / Effect | Requirement |
| --- | --- | --- | --- |
| wall | scrap x1 | Becomes solid wall | Floor |
| door | scrap x1, component x1 | Passable barrier placeholder | Walkable explored floor |
| light | component x1 | Reveals nearby explored machinery | Walkable explored floor |
| extractor | scrap x2, substrate x2, component x1 | Every 8s: component or substrate | At least one footprint cell on outlet |
| sensor | component x1, circuit x1 | Long reveal source | Outlet |
| charge pad | scrap x1, component x1, power cell x1 | Turns floor into outlet | Walkable explored floor |
| fabricator | scrap x2, substrate x1, circuit x1 | Every 12s: circuit or power cell | Outlet |
| dock | scrap x1, substrate x1 | Rest lowers mental tiredness | Walkable explored floor |
| repair bench | scrap x2, component x1 | Repairs bot condition; consumes scrap or component when used | Walkable explored floor |
| parts loom | substrate x2, circuit x1 | Consumes substrate x1 + circuit x1; every 14s: component or power cell | Outlet |
| maintenance dock | scrap x3, component x2, power cell x1 | Consumes scrap x1 every 24s; no visible benefit yet | Outlet |
| calibration shrine | circuit x1, power cell x1 | Placeholder for future mental/social recovery | Outlet |

## Current Progression Tree

```text
Start
  -> 3 bots
  -> explored floor/outlets nearby
  -> mine walls
      -> scrap
      -> chance: substrate
      -> rare chance: component
      -> build basics
          -> stockpile zones
          -> walls
          -> docks
          -> repair bench
          -> light
          -> door
      -> mine service cores / rich walls
          -> substrate
          -> component
          -> circuit
          -> power cell
          -> build outlet-gated structures
              -> extractor
                  -> component / substrate loop
              -> fabricator
                  -> circuit / power cell loop
              -> sensor
                  -> larger reveal
              -> parts loom
                  -> component / power cell loop, consumes substrate + circuit
              -> maintenance dock
                  -> consumes scrap upkeep, future service role
              -> calibration shrine
                  -> future mental/social role
```

## Current Problems

### Economy Clarity

- `scrap`, `component`, `substrate`, `circuit`, and `power cell` read like generic placeholder names. New player cannot infer tech tier, source, or use from names.
- `substrate` sounds biological or chemistry-heavy, but it acts as structural feedstock.
- `component` is too broad. Door hinges, machine actuators, and advanced parts all become same word.
- `circuit` and `power cell` are clear, but they appear before player has clear reason to care.
- `service core` sounds important, but player can mine it like ore. If it is rare loot node, name should signal salvage.
- `rich wall` is generic fantasy-mining language, not megastructure/droid language.
- `calibration shrine` uses religious language. This can work if AI cult flavor is intentional, but it may confuse players expecting machine ecology.
- `parts loom` is evocative but unclear. "Loom" implies textile unless fiction strongly supports woven circuitry.
- `maintenance dock` currently consumes scrap but gives no visible colony benefit, so it feels like resource deletion.

### Progression Clarity

- Fabricator needs circuit to build, then makes circuit. This creates bootstrap dependency: player must find circuit before building circuit production.
- Parts loom needs circuit and consumes circuit to make component or power cell. Since component is lower-tier than circuit, this can feel like downgrade.
- Extractor creates both component and substrate from nothing except outlet/time. Good prototype loop, but weak fiction: what material is being extracted?
- Power network is binary. Outlet exists or not. No throughput, battery, brownout, or grid planning pressure yet.
- Maintenance loop lacks feedback. Bots have condition decay and repair needs, but machine upkeep is not visible enough.
- Room progression is shallow: dock room satisfies one mood need, but no workshop/rec/recharge room economy yet.
- No research or tech gate. Current progression is resource-drop gated only.
- Stockpile has no filters/priorities. RimWorld-like economy needs storage specialization once resources grow.

## Better Economy Direction

Design goal: RimWorld-like colony economy, but every resource should feel like salvaged machine ecology inside a megastructure. Player should understand: mine wreckage, refine feedstock, fabricate parts, maintain minds/bodies, expand power, unlock deeper systems.

### Proposed Resource Set

| Tier | Proposed Name | Replaces / Adds | Meaning | Main Source | Main Use |
| --- | --- | --- | --- | --- | --- |
| 0 | scrap metal | scrap | Low-grade salvage | Common wall/debris mining | Walls, rough repairs, crude structures |
| 0 | polymer substrate | substrate | Printable structural feedstock | Debris, recycler, extractor | Floors, docks, casings, printer recipes |
| 1 | actuator parts | component | Mechanical/electromechanical parts | Salvage nodes, assembler | Doors, benches, limbs, machines |
| 1 | logic boards | circuit | Control boards | Service nodes, electronics bench | Sensors, AI workstations, fabricators |
| 1 | charge cells | power cell | Portable energy storage | Cell charger, service nodes | Charge pads, batteries, emergency power |
| 2 | memory cores | new | Identity/personality storage | Deep service cores, data extractor | AI upgrades, research, resurrection |
| 2 | servo limbs | new | Replacement body parts | Limb bench | Repair severe damage, worker upgrades |
| 2 | neural gel | new | Synthetic cooling/compute medium | Chem vat or rare nodes | Mood/mental recovery, advanced AI rooms |
| 3 | machine plasteel | new | High-grade megastructure alloy | Smelter/refiner | Strong walls, advanced machines |
| 3 | quantum relays | new | High-tier signal/power component | Advanced fab | Teleporters, long-range control, endgame |

### Rename Suggestions

| Current | Better Name | Reason |
| --- | --- | --- |
| scrap | scrap metal | Clear physical material |
| substrate | polymer substrate or printstock | Explains feedstock role |
| component | actuator parts | More concrete, droid-flavored |
| circuit | logic board | Clearer to non-technical players |
| power cell | charge cell | Shorter, ties to bot charge |
| service core | salvage core | Signals loot node, not base system player should preserve |
| rich wall | dense conduit vein | Fits megastructure material source |
| extractor | salvage extractor | Tells source and purpose |
| fabricator | microfab | Shorter, sci-fi, clear maker |
| parts loom | actuator loom or parts assembler | Less textile confusion |
| calibration shrine | calibration alcove | Keeps ritual tone without fantasy confusion |
| dock | rest dock | Clear bot bed equivalent |
| maintenance dock | service bay | Better colony maintenance meaning |

## Proposed Progression Tree

```text
Phase 1 - Survival Salvage
  Mine debris/walls
    -> scrap metal
    -> polymer substrate
  Build
    -> stockpile
    -> rest dock
    -> repair bench
    -> crude walls/doors
  Pressure
    -> bot energy
    -> condition decay
    -> sleep/mental tiredness

Phase 2 - Stable Workshop
  Build powered work area around outlet
    -> charge pad / battery
    -> salvage extractor
    -> parts assembler
  Produce
    -> actuator parts
    -> logic boards
  Unlock
    -> sensor mast
    -> better doors
    -> service bay
  Pressure
    -> machine upkeep
    -> stockpile filtering
    -> power demand

Phase 3 - Sentient AI Care
  Build rooms
    -> assigned rest dock room
    -> calibration alcove
    -> diagnostics room
  Produce
    -> memory cores
    -> neural gel
    -> servo limbs
  Unlock
    -> personality stabilization
    -> damaged bot recovery
    -> role specialization
  Pressure
    -> mood breaks
    -> identity degradation
    -> social needs

Phase 4 - Megastructure Expansion
  Refine high-tier materials
    -> machine plasteel
    -> quantum relays
  Build
    -> long-range scanner
    -> power relays
    -> hostile defense grid
    -> teleporter repair
  Pressure
    -> raids/hostiles
    -> power brownouts
    -> rare node control

Phase 5 - Ascent Objective
  Recover ancient systems
    -> root keys
    -> archive shards
    -> gate relays
  Build final chain
    -> uplink spire
    -> ascent gate
    -> colony mind backup
  Endgame choice
    -> escape upward
    -> merge with megastructure
    -> preserve droid colony
```

## Proposed Production Chains

```text
scrap metal + polymer substrate
  -> walls, docks, basic benches

scrap metal + actuator parts
  -> doors, repair bench, limb repairs

polymer substrate + logic boards
  -> parts assembler recipes

scrap metal + charge cells
  -> batteries, charge pads, emergency power

logic boards + memory cores + neural gel
  -> AI care, calibration, advanced research

machine plasteel + quantum relays + memory cores
  -> endgame scanners, teleporters, ascent systems
```

## Systems Needed To Support This

- Stockpile filters and priorities: critical once resources split into tiers.
- Work priorities: mining, hauling, crafting, repair, research, doctor/service work.
- Recipe data resources: move `BuildBlueprint` costs/production from code into data once list grows.
- Research or analysis bench: gates advanced recipes without only relying on rare random drops.
- Power grid model: generation, storage, draw, disabled machines during brownouts.
- Room stats: enclosure, cleanliness/rust, light, size, assigned owner, workshop type.
- Visible upkeep: service bay should prevent machine breakdown or improve repair speed, not silently eat scrap.
- Better source labels in tooltips: show "Drops: scrap metal, chance substrate" on mine targets.

## Short-Term Implementation Plan

1. Rename resources in UI only, keeping enum values stable to avoid save/data churn before save system exists.
2. Add stockpile tile capacity display and per-zone total display.
3. Add stockpile filters by item kind.
4. Change fabricator bootstrap:
   - extractor produces actuator parts + polymer substrate.
   - electronics bench turns actuator parts + charge into logic boards.
   - fabricator becomes tier-2, not first logic-board source.
5. Replace `maintenance dock` passive scrap sink with visible `service bay` effect:
   - repairs bots faster.
   - reduces condition decay for assigned bots.
   - later prevents machine breakdowns.
6. Rename `calibration shrine` to `calibration alcove` unless religious AI cult tone becomes explicit.
7. Add first research object: `analysis bench`.
   - consumes memory cores or salvage cores.
   - unlocks sensor, microfab, service bay, power storage.
8. Add room progression:
   - rest dock room for sleep/mood.
   - workshop for crafting speed.
   - diagnostics room for repair/mental recovery.

