# Fallen Ascent Current Mechanics

Snapshot of prototype mechanics as implemented in code.

## Game Flow

- Main scene creates or reuses selected world site data, then opens colony site.
- World map generates deterministic sites from world seed.
- Colony site builds finite generated map from site seed.
- Player manages bots, designates work, places structures, and stores mined resources.
- Game speed uses global time scale: paused, 1x, 2x, 3x.

## Colony Map

- Grid-based 2D map using 16 px tiles.
- Terrain types include floor, wall, debris, conduit, rust, outlet, service core, and rich wall.
- Map is generated from seed through `TerrainGenerator`.
- Fog of war tracks explored cells and blocks orders into unseen space.
- Camera has world bounds, pan, zoom, and edge-scroll behavior.

## Bots

- Initial colony spawns 3 bots near origin.
- Bot names come from name pool: Echo, Rook, Cipher, Spark, Null, Tweak, Scrap, Clink, Bolt, Quirk, Shift, Flick, Sync, Blink, and more.
- Bots can be selected singly or with drag box.
- Selected bots receive right-click direct orders.
- Bots show selected ring, carried-item marker, energy bar, and screen-scale action bubble.
- Bot stats: energy, condition, mental tiredness, social score, carried item, state, current job.
- Bot history records recent actions: orders, movement, pickup, hauling, mining, building, repair, rest, chat.

## Bot Needs

- Energy drains while idle, moving, and working.
- Low energy makes bots seek nearest reachable outlet.
- Critical energy interrupts current work and forces charge seeking.
- Charging restores energy at outlets.
- Condition decays while moving and working.
- Low condition makes bots seek repair bench or mechanic dock.
- Repair consumes colony materials when available.
- Mental tiredness rises during work and idle life.
- High mental tiredness makes bots seek dock rest.
- Social score rises during chat.

These needs are current food-like pressure loop for sentient bots: colony must keep charge access, repair materials, and rest/service structures available so bots stay productive.

## Jobs

- Job board owns mine, haul, and build jobs.
- Workers claim nearest available job.
- Jobs can be cancelled and released.
- Mine jobs target mineable walls, rich walls, and service cores.
- Haul jobs move loose items into stockpile zones.
- Build jobs deliver ingredients one item at a time, then complete blueprint.
- Direct orders override current work.
- Chat invites pause current work by releasing active job and sending both bots into chat behavior.

## Direct Orders

- Left-click selects bots or structures.
- Left-drag selects multiple bots.
- Right-click explored mineable tile: selected bot mines it.
- Right-click explored walkable tile: selected bots move in loose formation.
- Shift-right-click explored walkable tile: selected bot builds wall.
- Right-click outlet: selected bot charges there.
- Issued direct order flashes selected target tile.

## Resources

- Loose and stored item stacks exist on grid cells.
- Stack kinds: scrap, component, substrate, circuit, power cell.
- Mining always drops scrap.
- Mining can also drop substrate and components.
- Service cores and rich walls have better rare drops.
- Items can be carried by bots, dropped, reserved, or merged in stockpiles.
- Stockpiles store item stacks and expose counts to HUD.

## Structures

- Buildable structures use blueprint definitions with footprint, cost, duration, tooltip, color, and production data.
- Wall becomes terrain wall.
- Door is passable controlled barrier with its own animation atlas.
- Sensor provides longer reveal source.
- Charge turns floor into outlet.
- Extractor pulls plating or mechanism from exposed systems.
- Crafting bench speeds crafted-object work.
- Dock bed reduces bot mental tiredness through rest.
- Repair bench restores bot condition and consumes repair materials.
- Assembler press consumes scrap to produce plating or mechanism.
- Mechanic dock heals limb damage inside Mechanic Rooms.
- Research bench generates wisdom.
- Fabricator assembles datacores, charge cells, and rudimentary sensors.
- Replication cradle creates new workers from refined inputs.
- Crafting spot crafts placeable objects.

## UI

- Top HUD shows worker count, job count, active tool, and resource counts.
- Command palette has Orders, Zones, Rooms, Workshops, Building, Storage, Visibility, and Objects tabs.
- Tool buttons show icons and detailed tooltips.
- Selection panel shows worker cards or structure card.
- Worker cards show stats, meters, and scrollable thought history.
- Structure card shows grid, description, production, inputs, progress, cycle, and blocked state.
- Tile tooltip reports terrain, occupants, structures, stockpile status, and designation status.
- Settings menu supports display, vsync, and FPS options.

## Designation Tools

- Mine tool toggles mine jobs on mineable cells.
- Stockpile tool paints rectangular storage zones.
- Remove stockpile deletes zone under cursor.
- Build tools place ghost preview and queue blueprint construction.
- Invalid build ghost draws red.
- Cancel clears active tool.

## Visibility

- Fog of war hides unexplored cells.
- Bots and reveal structures expand known space.
- Orders are rejected on unexplored cells.
- Tool previews respect explored state.

## Current Limits

- No save/load yet.
- No combat or hostile entities yet.
- No job priorities yet.
- Direct orders replace current manual order; no queue yet.
- Chat pauses work by releasing job, not by storing exact resume point.
- Calibration shrine has placeholder role.
- Power network has simple outlets, no throughput or storage simulation yet.
