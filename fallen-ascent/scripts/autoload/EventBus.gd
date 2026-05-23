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
##
## Rules:
##   - No state, no logic. This file holds signal declarations only.
##   - Payloads use typed primitives or Resource subclasses — no Dictionaries.

signal site_selected(site: Resource)
signal game_speed_changed(speed: float)
signal camera_moved(world_pos: Vector2, zoom: Vector2)
signal chunk_loaded(chunk_coord: Vector2i)
signal chunk_unloaded(chunk_coord: Vector2i)
