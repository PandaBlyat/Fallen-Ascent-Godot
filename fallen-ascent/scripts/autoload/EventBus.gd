extends Node
##
## Global signal hub. The ONLY place cross-system signals are declared.
##
## Catalogue (keep this comment in sync when adding signals):
##   site_selected(site)              - emitted when the player picks a colony
##                                      site on the world map. Payload: SiteData.
##   game_speed_changed(speed)        - emitted when GameState.game_speed changes.
##                                      Payload: float (0.0 = paused).
##   camera_moved(world_pos, zoom)    - emitted by CameraController when its
##                                      position/zoom changes beyond an epsilon.
##                                      Throttled — NOT once per frame.
##   chunk_loaded(chunk_coord)        - emitted by ChunkManager after a chunk
##                                      has been instantiated and populated.
##   chunk_unloaded(chunk_coord)      - emitted just before a chunk is freed.
##   colony_load_progress(loaded,total)
##                                    - emitted by ChunkManager while initial
##                                      colony map preload drains over frames.
##   tile_changed(grid, new_tile)     - emitted by ChunkManager after a tile is
##                                      mutated via set_tile_at. Payload: global
##                                      grid coord (Vector2i) + new tile id.
##   worker_selected(worker)          - legacy single-worker selection mirror.
##   workers_selected(workers)        - emitted by SelectionController when the
##                                      player changes worker selection.
##   structure_selected(id, anchor)   - emitted by SelectionController when a
##                                      built structure is selected. id -1 clears.
##   stockpile_selected(zone)         - emitted by SelectionController when a
##                                      stockpile zone is selected. null clears.
##   build_job_selected(anchor)       - emitted by SelectionController when a
##                                      queued construction job is selected.
##                                      UNREACHABLE clears.
##   structure_built(manager)         - emitted after StructureManager places
##                                      or changes static objects.
##   visibility_changed(bounds)       - emitted after FogOfWar changes sight.
##                                      Payload: changed grid bounds only.
##   bot_inspected(node, faction)     - emitted by SelectionController when the
##                                      player single-clicks a neutral/hostile.
##                                      Payload: Node (NeutralBot or HostileBot)
##                                      or null to clear; int faction id
##                                      (1=neutral, 2=hostile).
##   combat_hit(attacker, target, dmg)- emitted after a successful melee swing.
##                                      Payload: Node, Node, float.
##   combat_dodged(attacker, target)  - emitted when a target dodges a swing.
##                                      Payload: Node, Node.
##   combatant_died(node, faction)    - emitted just before a downed combatant
##                                      is queue_freed. Payload: Node, int
##                                      faction id (0=colony, 1=neutral,
##                                      2=hostile).
##   hostile_spawned(node)            - emitted by HostileSpawner after a new
##                                      hostile is added to the tree.
##   wisdom_changed(new_total)        - emitted by TechManager when the wisdom
##                                      pool changes. Payload: float.
##   tech_unlocked(tech_id)           - emitted by TechManager after a tech
##                                      node is unlocked. Payload: StringName.
##   worker_spawned_from_cradle(worker)
##                                    - emitted by StructureManager after a
##                                      Replication Cradle finishes a build cycle
##                                      and a new Worker is added to the tree.
##   fabricator_needs_inputs(anchor,missing_kinds)
##                                    - emitted when automatic production stalls
##                                      because required inputs are absent.
##
## Rules:
##   - No state, no logic. This file holds signal declarations only.
##   - Payloads use typed primitives or Resource subclasses — no Dictionaries.

@warning_ignore_start("unused_signal")
signal site_selected(site: Resource)
signal game_speed_changed(speed: float)
signal camera_moved(world_pos: Vector2, zoom: Vector2)
signal chunk_loaded(chunk_coord: Vector2i)
signal chunk_unloaded(chunk_coord: Vector2i)
signal colony_load_progress(loaded: int, total: int)
signal tile_changed(grid: Vector2i, new_tile: int)
signal worker_selected(worker: Node)
signal workers_selected(workers: Array)
signal structure_selected(id: int, anchor: Vector2i)
signal stockpile_selected(zone: Node)
signal build_job_selected(anchor: Vector2i)
signal structure_built(manager: Node)
signal visibility_changed(bounds: Rect2i)
signal bot_inspected(node: Node, faction: int)
signal combat_hit(attacker: Node, target: Node, damage: float)
signal combat_dodged(attacker: Node, target: Node)
signal combatant_died(node: Node, faction: int)
signal hostile_spawned(node: Node)
signal wisdom_changed(new_total: float)
signal tech_unlocked(tech_id: StringName)
signal worker_spawned_from_cradle(worker: Node)
signal fabricator_needs_inputs(anchor: Vector2i, missing_kinds: Array)
@warning_ignore_restore("unused_signal")
