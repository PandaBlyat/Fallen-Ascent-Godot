class_name FogOfWar
extends Node2D
##
## Session-only colony visibility. Explored cells stay remembered, current
## sight around workers/lights is bright.
##

const WORKER_SIGHT_RADIUS: int = 7
const REFRESH_SECONDS: float = 0.18
const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 0.985)
const MEMORY_COLOR := Color(0.0, 0.0, 0.0, 0.55)

@export var camera_path: NodePath
@export var chunk_manager_path: NodePath
@export var workers_root_path: NodePath
@export var structure_manager_path: NodePath

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _workers_root: Node2D
var _structure_manager: StructureManager
var _explored: Dictionary = {}                   ## Vector2i -> true
var _visible: Dictionary = {}                    ## Vector2i -> true
var _accum: float = 0.0


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_workers_root = get_node(workers_root_path) as Node2D
	_structure_manager = get_node(structure_manager_path) as StructureManager
	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.structure_built.connect(_on_structure_built)
	call_deferred("_refresh_visibility")


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	_refresh_visibility()


func is_explored(grid: Vector2i) -> bool:
	return _explored.has(grid)


func is_cell_visible(grid: Vector2i) -> bool:
	return _visible.has(grid)


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	queue_redraw()


func _on_structure_built(_manager: Node) -> void:
	_refresh_visibility()


func _refresh_visibility() -> void:
	var next_visible: Dictionary = {}
	if _workers_root != null:
		for child in _workers_root.get_children():
			var worker := child as Worker
			if worker == null:
				continue
			_reveal_into(next_visible, worker.current_grid(), WORKER_SIGHT_RADIUS)
	if _structure_manager != null:
		for source in _structure_manager.reveal_sources():
			_reveal_into(next_visible, source["grid"] as Vector2i, int(source["radius"]))
	_visible = next_visible
	for key in _visible.keys():
		_explored[key] = true
	EventBus.visibility_changed.emit(_chunk_manager.map_grid_bounds())
	queue_redraw()


func _reveal_into(target: Dictionary, center: Vector2i, radius: int) -> void:
	var r2: int = radius * radius
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var g := Vector2i(x, y)
			if not _chunk_manager.is_grid_in_map(g):
				continue
			var d := g - center
			if d.x * d.x + d.y * d.y > r2:
				continue
			target[g] = true


func _draw() -> void:
	if _camera == null or _chunk_manager == null:
		return
	var bounds: Rect2i = _visible_grid_bounds()
	var map_bounds: Rect2i = _chunk_manager.map_grid_bounds()
	var lo := Vector2i(
		maxi(bounds.position.x, map_bounds.position.x),
		maxi(bounds.position.y, map_bounds.position.y),
	)
	var hi := Vector2i(
		mini(bounds.position.x + bounds.size.x, map_bounds.position.x + map_bounds.size.x),
		mini(bounds.position.y + bounds.size.y, map_bounds.position.y + map_bounds.size.y),
	)
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var g := Vector2i(x, y)
			if _visible.has(g):
				continue
			var color: Color = MEMORY_COLOR if _explored.has(g) else UNEXPLORED_COLOR
			var origin := Vector2(x * Chunk.TILE_PIXELS, y * Chunk.TILE_PIXELS)
			draw_rect(Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)), color)


func _visible_grid_bounds() -> Rect2i:
	var viewport_size: Vector2 = get_viewport_rect().size
	var zoom: Vector2 = _camera.zoom
	var world_size := Vector2(viewport_size.x / zoom.x, viewport_size.y / zoom.y)
	var top_left: Vector2 = _camera.global_position - world_size * 0.5
	var bottom_right: Vector2 = _camera.global_position + world_size * 0.5
	var lo := Vector2i(
		int(floor(top_left.x / Chunk.TILE_PIXELS)) - 2,
		int(floor(top_left.y / Chunk.TILE_PIXELS)) - 2,
	)
	var hi := Vector2i(
		int(ceil(bottom_right.x / Chunk.TILE_PIXELS)) + 2,
		int(ceil(bottom_right.y / Chunk.TILE_PIXELS)) + 2,
	)
	return Rect2i(lo, hi - lo)
