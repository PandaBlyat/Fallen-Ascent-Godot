class_name FogOfWar
extends Node2D
##
## Session-only colony visibility. Explored cells stay remembered, current
## sight around workers/lights is bright.
##

const WORKER_SIGHT_RADIUS: int = 7
const REFRESH_SECONDS: float = 0.18
const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 0.994)
const MEMORY_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const LineOfSight: Script = preload("res://scripts/util/LineOfSight.gd")

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
var _visibility_dirty: bool = true
var _last_source_signature: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_workers_root = get_node(workers_root_path) as Node2D
	_structure_manager = get_node(structure_manager_path) as StructureManager
	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.structure_built.connect(_on_structure_built)
	EventBus.tile_changed.connect(_on_tile_changed)
	call_deferred("_refresh_visibility")


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_SECONDS:
		return
	_accum = 0.0
	var signature: PackedInt32Array = _collect_source_signature()
	if not _visibility_dirty and _same_signature(signature, _last_source_signature):
		return
	_refresh_visibility(signature)


func is_explored(grid: Vector2i) -> bool:
	return _explored.has(grid)


func is_cell_visible(grid: Vector2i) -> bool:
	return _visible.has(grid)


func explored_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in _explored.keys():
		out.append(key as Vector2i)
	return out


func is_frontier(grid: Vector2i) -> bool:
	if not _explored.has(grid):
		return false
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for off in OFFSETS:
		var candidate: Vector2i = grid + off
		if _chunk_manager.is_grid_in_map(candidate) and not _explored.has(candidate):
			return true
	return false


func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void:
	queue_redraw()


func _on_structure_built(_manager: Node) -> void:
	_visibility_dirty = true
	_refresh_visibility()


func _on_tile_changed(_grid: Vector2i, _new_tile: int) -> void:
	_visibility_dirty = true


func _refresh_visibility(signature: PackedInt32Array = PackedInt32Array()) -> void:
	if signature.is_empty():
		signature = _collect_source_signature()
	var next_visible: Dictionary = {}
	for i in range(0, signature.size(), 3):
		_reveal_into(next_visible, Vector2i(signature[i], signature[i + 1]), signature[i + 2])
	var changed_bounds: Rect2i = _changed_visibility_bounds(_visible, next_visible)
	_visible = next_visible
	for key in _visible.keys():
		_explored[key] = true
	_last_source_signature = signature
	_visibility_dirty = false
	if changed_bounds.size != Vector2i.ZERO:
		EventBus.visibility_changed.emit(changed_bounds)
		queue_redraw()


func _collect_source_signature() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _workers_root != null:
		for child in _workers_root.get_children():
			var worker := child as Worker
			if worker == null:
				continue
			var grid: Vector2i = worker.current_grid()
			out.append(grid.x)
			out.append(grid.y)
			out.append(WORKER_SIGHT_RADIUS)
	if _structure_manager != null:
		for source in _structure_manager.reveal_sources():
			var grid: Vector2i = source["grid"] as Vector2i
			out.append(grid.x)
			out.append(grid.y)
			out.append(int(source["radius"]))
	return out


func _same_signature(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func _changed_visibility_bounds(previous: Dictionary, next: Dictionary) -> Rect2i:
	var first := true
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	for key in next.keys():
		if previous.has(key):
			continue
		var cell: Vector2i = key as Vector2i
		if first:
			lo = cell
			hi = cell + Vector2i.ONE
			first = false
		else:
			lo.x = mini(lo.x, cell.x)
			lo.y = mini(lo.y, cell.y)
			hi.x = maxi(hi.x, cell.x + 1)
			hi.y = maxi(hi.y, cell.y + 1)
	for key in previous.keys():
		if next.has(key):
			continue
		var cell: Vector2i = key as Vector2i
		if first:
			lo = cell
			hi = cell + Vector2i.ONE
			first = false
		else:
			lo.x = mini(lo.x, cell.x)
			lo.y = mini(lo.y, cell.y)
			hi.x = maxi(hi.x, cell.x + 1)
			hi.y = maxi(hi.y, cell.y + 1)
	if first:
		return Rect2i()
	return Rect2i(lo, hi - lo)


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
			if not LineOfSight.has_los(_chunk_manager, center, g):
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
		var run_active: bool = false
		var run_start: int = lo.x
		var run_color := Color.TRANSPARENT
		for x in range(lo.x, hi.x):
			var g := Vector2i(x, y)
			if _visible.has(g):
				if run_active:
					_draw_fog_run(run_start, x, y, run_color)
					run_active = false
				continue
			var color: Color = MEMORY_COLOR if _explored.has(g) else UNEXPLORED_COLOR
			if run_active and color == run_color:
				continue
			if run_active:
				_draw_fog_run(run_start, x, y, run_color)
			run_active = true
			run_start = x
			run_color = color
		if run_active:
			_draw_fog_run(run_start, hi.x, y, run_color)


func _draw_fog_run(start_x: int, end_x: int, y: int, color: Color) -> void:
	if end_x <= start_x:
		return
	var origin := Vector2(start_x * Chunk.TILE_PIXELS, y * Chunk.TILE_PIXELS)
	var size := Vector2((end_x - start_x) * Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)
	draw_rect(Rect2(origin, size), color)


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
