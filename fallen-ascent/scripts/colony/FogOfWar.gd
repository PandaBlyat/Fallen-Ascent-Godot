class_name FogOfWar
extends Node2D
##
## Session-only colony visibility. Explored cells stay remembered, current
## sight around workers/lights is bright.
##

const WORKER_SIGHT_RADIUS: int = 7
const REFRESH_SECONDS: float = 0.18
const FOG_Z_INDEX: int = 900
## Fully opaque so glowing tiles (acid, lights) under undiscovered fog
## don't leak through.
const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const MEMORY_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const LIT_MEMORY_MIN_ALPHA: float = 0.10
const VISIBLE_EDGE_ALPHA: float = 0.10
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
var _visible: Dictionary = {}                    ## Vector2i -> sight strength 0..1
var _lit_memory: Dictionary = {}                 ## Vector2i -> light strength 0..1
var _accum: float = 0.0
## Wall-clock guard so visibility rebuilds don't pile up at high game speeds —
## the player can crank `Engine.time_scale` without the LOS recompute and
## mask upload dominating real-frame time.
var _last_refresh_ms: int = 0
var _visibility_dirty: bool = true
var _last_source_signature: PackedInt32Array = PackedInt32Array()
var _visibility_mask_texture: ImageTexture = null
var _light_mask_texture: ImageTexture = null
var _mask_origin: Vector2i = Vector2i.ZERO
var _mask_size: Vector2i = Vector2i.ONE
var _light_dirty: bool = true                    ## rebuild light mask only when sources / explored set actually change
var _light_buffer: PackedByteArray = PackedByteArray()
var _visibility_buffer: PackedByteArray = PackedByteArray()
var _vis_default_buffer: PackedByteArray = PackedByteArray()
var _light_default_buffer: PackedByteArray = PackedByteArray()


func _ready() -> void:
	z_index = FOG_Z_INDEX
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_workers_root = get_node(workers_root_path) as Node2D
	_structure_manager = get_node(structure_manager_path) as StructureManager
	EventBus.camera_moved.connect(_on_camera_moved)
	EventBus.structure_built.connect(_on_structure_built)
	EventBus.tile_changed.connect(_on_tile_changed)
	if SettingsManager != null:
		SettingsManager.settings_changed.connect(queue_redraw)
	call_deferred("_refresh_visibility")


func _process(_delta: float) -> void:
	# Gate on wall clock, not delta — at high `Engine.time_scale` delta is
	# multiplied, which would call _refresh_visibility many times per real
	# second even though nothing on screen needs it.
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_refresh_ms < int(REFRESH_SECONDS * 1000.0):
		return
	_last_refresh_ms = now_ms
	var signature: PackedInt32Array = _collect_source_signature()
	if not _visibility_dirty and _same_signature(signature, _last_source_signature):
		return
	_refresh_visibility(signature)


func is_explored(grid: Vector2i) -> bool:
	return _explored.has(grid)


func is_cell_visible(grid: Vector2i) -> bool:
	return _visible.has(grid)


func visibility_mask_texture() -> Texture2D:
	return _visibility_mask_texture


func light_mask_texture() -> Texture2D:
	return _light_mask_texture


func visibility_mask_origin() -> Vector2i:
	return _mask_origin


func visibility_mask_size() -> Vector2i:
	return _mask_size


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
	_light_dirty = true
	_refresh_visibility()


func _on_tile_changed(_grid: Vector2i, _new_tile: int) -> void:
	_visibility_dirty = true
	_light_dirty = true


func _refresh_visibility(signature: PackedInt32Array = PackedInt32Array()) -> void:
	if signature.is_empty():
		signature = _collect_source_signature()
	var next_visible: Dictionary = {}
	for i in range(0, signature.size(), 3):
		_reveal_into(next_visible, Vector2i(signature[i], signature[i + 1]), signature[i + 2])
	var changed_bounds: Rect2i = _changed_visibility_bounds(_visible, next_visible)
	_visible = next_visible
	var prev_explored_size: int = _explored.size()
	for key in _visible.keys():
		_explored[key] = true
	# Light memory depends on the explored set; if it grew this tick, the
	# light mask buffer needs another pass.
	if _explored.size() != prev_explored_size:
		_light_dirty = true
	_last_source_signature = signature
	_visibility_dirty = false
	_rebuild_mask_textures()
	if changed_bounds.size != Vector2i.ZERO or not signature.is_empty():
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
			var dist2: int = d.x * d.x + d.y * d.y
			if dist2 > r2:
				continue
			if not LineOfSight.has_los(_chunk_manager, center, g):
				continue
			var dist: float = sqrt(float(dist2))
			var strength: float = clampf(1.0 - pow(dist / float(radius), 1.85), 0.08, 1.0)
			target[g] = maxf(float(target.get(g, 0.0)), strength)


func _rebuild_mask_textures() -> void:
	if _chunk_manager == null:
		return
	var bounds: Rect2i = _chunk_manager.map_grid_bounds()
	_mask_origin = bounds.position
	var prev_size: Vector2i = _mask_size
	_mask_size = Vector2i(maxi(1, bounds.size.x), maxi(1, bounds.size.y))
	var pixel_count: int = _mask_size.x * _mask_size.y
	var byte_count: int = pixel_count * 4
	if _vis_default_buffer.size() != byte_count or prev_size != _mask_size:
		_vis_default_buffer.resize(byte_count)
		_light_default_buffer.resize(byte_count)
		# Default visibility: unexplored black (a=255). Default light: zero.
		for i in pixel_count:
			var b: int = i * 4
			_vis_default_buffer[b] = 0
			_vis_default_buffer[b + 1] = 0
			_vis_default_buffer[b + 2] = 0
			_vis_default_buffer[b + 3] = 255
			_light_default_buffer[b] = 0
			_light_default_buffer[b + 1] = 0
			_light_default_buffer[b + 2] = 0
			_light_default_buffer[b + 3] = 0
		_light_dirty = true
	_visibility_buffer = _vis_default_buffer.duplicate()
	var width: int = _mask_size.x
	var bx0: int = bounds.position.x
	var by0: int = bounds.position.y
	var bx1: int = bx0 + bounds.size.x
	var by1: int = by0 + bounds.size.y
	for key in _explored.keys():
		var cell: Vector2i = key as Vector2i
		if cell.x < bx0 or cell.x >= bx1 or cell.y < by0 or cell.y >= by1:
			continue
		var idx: int = ((cell.y - _mask_origin.y) * width + (cell.x - _mask_origin.x)) * 4
		_visibility_buffer[idx] = 255          # R: explored flag
		_visibility_buffer[idx + 1] = 0        # G: visible strength (0 = explored-only)
		_visibility_buffer[idx + 2] = 0
		_visibility_buffer[idx + 3] = 255
	for key in _visible.keys():
		var cell2: Vector2i = key as Vector2i
		if cell2.x < bx0 or cell2.x >= bx1 or cell2.y < by0 or cell2.y >= by1:
			continue
		var strength: float = clampf(float(_visible.get(cell2, 1.0)), 0.0, 1.0)
		var s_byte: int = int(strength * 255.0)
		var idx2: int = ((cell2.y - _mask_origin.y) * width + (cell2.x - _mask_origin.x)) * 4
		_visibility_buffer[idx2] = 255
		_visibility_buffer[idx2 + 1] = s_byte
		_visibility_buffer[idx2 + 2] = s_byte
		_visibility_buffer[idx2 + 3] = 255
	var visibility_image := Image.create_from_data(_mask_size.x, _mask_size.y, false, Image.FORMAT_RGBA8, _visibility_buffer)
	if _light_dirty:
		_rebuild_light_buffer(bounds)
		_light_dirty = false
	var light_image := Image.create_from_data(_mask_size.x, _mask_size.y, false, Image.FORMAT_RGBA8, _light_buffer)
	if _visibility_mask_texture == null or _visibility_mask_texture.get_width() != _mask_size.x \
			or _visibility_mask_texture.get_height() != _mask_size.y:
		_visibility_mask_texture = ImageTexture.create_from_image(visibility_image)
	else:
		_visibility_mask_texture.update(visibility_image)
	if _light_mask_texture == null or _light_mask_texture.get_width() != _mask_size.x \
			or _light_mask_texture.get_height() != _mask_size.y:
		_light_mask_texture = ImageTexture.create_from_image(light_image)
	else:
		_light_mask_texture.update(light_image)


func _rebuild_light_buffer(bounds: Rect2i) -> void:
	_lit_memory.clear()
	_light_buffer = _light_default_buffer.duplicate()
	if _structure_manager == null or not _structure_manager.has_method("visual_light_sources"):
		return
	var sources: Array = _structure_manager.call("visual_light_sources") as Array
	var width: int = _mask_size.x
	var bx0: int = bounds.position.x
	var by0: int = bounds.position.y
	var bx1: int = bx0 + bounds.size.x
	var by1: int = by0 + bounds.size.y
	for raw_source in sources:
		var source := raw_source as Dictionary
		var center: Vector2i = source.get("grid", Vector2i.ZERO) as Vector2i
		var radius: int = int(source.get("radius", 0))
		if radius <= 0:
			continue
		if bool(source.get("requires_visible_source", false)) and not _visible.has(center):
			continue
		var color: Color = source.get("color", Color(1.0, 0.88, 0.45, 1.0)) as Color
		var intensity: float = clampf(float(source.get("intensity", 1.0)), 0.0, 2.0)
		var r2: int = radius * radius
		var inv_r: float = 1.0 / float(radius)
		for y in range(center.y - radius, center.y + radius + 1):
			if y < by0 or y >= by1:
				continue
			for x in range(center.x - radius, center.x + radius + 1):
				if x < bx0 or x >= bx1:
					continue
				var g := Vector2i(x, y)
				if not _explored.has(g):
					continue
				var dx: int = x - center.x
				var dy: int = y - center.y
				var dist2: int = dx * dx + dy * dy
				if dist2 > r2:
					continue
				if not LineOfSight.has_los(_chunk_manager, center, g):
					continue
				var dist: float = sqrt(float(dist2))
				var falloff: float = pow(maxf(0.0, 1.0 - dist * inv_r), 1.65) * intensity
				_lit_memory[g] = maxf(float(_lit_memory.get(g, 0.0)), falloff)
				var idx: int = ((y - _mask_origin.y) * width + (x - _mask_origin.x)) * 4
				var pr: int = _light_buffer[idx]
				var pg: int = _light_buffer[idx + 1]
				var pb: int = _light_buffer[idx + 2]
				var pa: int = _light_buffer[idx + 3]
				_light_buffer[idx] = mini(255, pr + int(color.r * falloff * 255.0))
				_light_buffer[idx + 1] = mini(255, pg + int(color.g * falloff * 255.0))
				_light_buffer[idx + 2] = mini(255, pb + int(color.b * falloff * 255.0))
				_light_buffer[idx + 3] = mini(255, pa + int(falloff * 255.0))


func _draw() -> void:
	if _camera == null or _chunk_manager == null:
		return
	var darkness: float = clampf(SettingsManager.overall_darkness, 0.0, 2.0)
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
				var sight_strength: float = clampf(float(_visible.get(g, 1.0)), 0.0, 1.0)
				if sight_strength < 0.92:
					var edge_alpha: float = (1.0 - sight_strength) * VISIBLE_EDGE_ALPHA * darkness
					_draw_fog_run(x, x + 1, y, Color(0.0, 0.0, 0.0, edge_alpha))
				if run_active:
					_draw_fog_run(run_start, x, y, run_color)
					run_active = false
				continue
			var color: Color = UNEXPLORED_COLOR
			if _explored.has(g):
				var lit: float = clampf(float(_lit_memory.get(g, 0.0)), 0.0, 1.0)
				var alpha: float = lerpf(MEMORY_COLOR.a, LIT_MEMORY_MIN_ALPHA, smoothstep(0.05, 0.95, lit))
				color = Color(MEMORY_COLOR.r, MEMORY_COLOR.g, MEMORY_COLOR.b, clampf(alpha * darkness, 0.0, 1.0))
			else:
				color = Color(UNEXPLORED_COLOR.r, UNEXPLORED_COLOR.g, UNEXPLORED_COLOR.b, clampf(UNEXPLORED_COLOR.a * darkness, 0.0, 1.0))
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
