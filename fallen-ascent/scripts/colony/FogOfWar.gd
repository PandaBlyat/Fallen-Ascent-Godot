class_name FogOfWar extends Node2D

## Session-only colony visibility. Explored cells stay remembered, current
## sight around workers/lights is bright.

const WORKER_SIGHT_RADIUS: int = 8 
const REFRESH_SECONDS: float = 0.18 
const FOG_Z_INDEX: int = 900

## Fully opaque so glowing tiles (acid, lights) under undiscovered fog don't leak through.
const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 1.0) 
const MEMORY_COLOR := Color(0.0, 0.0, 0.0, 0.10) 
const LIT_MEMORY_MIN_ALPHA: float = 0.10 
const VISIBLE_EDGE_ALPHA: float = 0.05 
const LineOfSight: Script = preload("res://scripts/util/LineOfSight.gd")

@export var camera_path: NodePath 
@export var chunk_manager_path: NodePath 
@export var workers_root_path: NodePath 
@export var structure_manager_path: NodePath

var _camera: Camera2D 
var _chunk_manager: ChunkManager 
var _workers_root: Node2D 
var _structure_manager: StructureManager 

## Maintain dictionaries for external/internal system queries to preserve API compatibility
var _explored: Dictionary = {} ## Vector2i -> true 
var _visible: Dictionary = {} ## Vector2i -> sight strength 0..1 
var _lit_memory: Dictionary = {} ## Vector2i -> light strength 0..1 
var _accum: float = 0.0

## Flat array helpers for rendering and lookup optimizations
var _map_width: int = 0
var _map_height: int = 0
var _map_origin: Vector2i = Vector2i.ZERO
var _explored_flat: PackedByteArray = PackedByteArray()
var _visible_flat: PackedFloat32Array = PackedFloat32Array()
var _lit_memory_flat: PackedFloat32Array = PackedFloat32Array()

## Wall-clock guard so visibility rebuilds don't pile up at high game speeds
var _last_refresh_ms: int = 0 
var _visibility_dirty: bool = true 
var _last_source_signature: PackedInt32Array = PackedInt32Array() 
var _visibility_mask_texture: ImageTexture = null 
var _light_mask_texture: ImageTexture = null 
var _mask_origin: Vector2i = Vector2i.ZERO 
var _mask_size: Vector2i = Vector2i.ONE 
var _light_dirty: bool = true 

## Persistent Image buffers
var _visibility_image: Image = null 
var _light_image: Image = null 
var _explored_cells_cache: Array[Vector2i] = [] 
var _explored_cells_dirty: bool = true

func _ready() -> void: 
	process_mode = Node.PROCESS_MODE_ALWAYS 
	z_index = FOG_Z_INDEX 
	_camera = get_node(camera_path) as Camera2D 
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager 
	_workers_root = get_node(workers_root_path) as Node2D 
	_structure_manager = get_node(structure_manager_path) as StructureManager 
	
	EventBus.structure_built.connect(_on_structure_built)
	EventBus.tile_changed.connect(_on_tile_changed)
	EventBus.camera_moved.connect(_on_camera_moved) 
	
	if SettingsManager != null:
		SettingsManager.settings_changed.connect(queue_redraw)
	call_deferred("_refresh_visibility")

func _process(_delta: float) -> void: 
	var now_ms: int = Time.get_ticks_msec() 
	if now_ms - _last_refresh_ms < int(REFRESH_SECONDS * 1000.0): 
		return 
	_last_refresh_ms = now_ms 
	
	var signature: PackedInt32Array = _collect_source_signature() 
	if not _visibility_dirty and _same_signature(signature, _last_source_signature): 
		return 
	_refresh_visibility(signature)

func is_explored(grid: Vector2i) -> bool: 
	var idx := _grid_to_index(grid)
	return idx != -1 and _explored_flat[idx] == 1

func capture_save() -> Dictionary: 
	var cells: Array = [] 
	for c in _explored: 
		cells.append(c) 
	return {"explored": cells}

func restore_save(data: Dictionary) -> void: 
	_explored.clear()
	for c in data.get("explored", []) as Array: 
		_explored[c as Vector2i] = true 
	
	_explored_cells_dirty = true 
	_visibility_dirty = true 
	_visibility_image = null 
	call_deferred("_refresh_visibility")

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
	if not _explored_cells_dirty: 
		return _explored_cells_cache 
	_explored_cells_cache.clear() 
	for cell in _explored: 
		_explored_cells_cache.append(cell as Vector2i) 
	_explored_cells_dirty = false 
	return _explored_cells_cache

func is_frontier(grid: Vector2i) -> bool: 
	var idx := _grid_to_index(grid)
	if idx == -1 or _explored_flat[idx] == 0: 
		return false
		
	const OFFSETS: Array[Vector2i] = [ 
		Vector2i(1, 0), 
		Vector2i(-1, 0), 
		Vector2i(0, 1), 
		Vector2i(0, -1), 
	] 
	for off in OFFSETS: 
		var candidate: Vector2i = grid + off 
		var c_idx := _grid_to_index(candidate)
		if c_idx != -1 and _explored_flat[c_idx] == 0: 
			return true 
	return false

func _on_structure_built(_manager: Node) -> void: 
	_visibility_dirty = true 
	_light_dirty = true 
	_refresh_visibility()

func _on_tile_changed(_grid: Vector2i, _new_tile: int) -> void: 
	_visibility_dirty = true 
	_light_dirty = true

func _on_camera_moved(_world_pos: Vector2, _zoom: Vector2) -> void: 
	queue_redraw()

func _grid_to_index(grid: Vector2i) -> int:
	var x := grid.x - _map_origin.x
	var y := grid.y - _map_origin.y
	if x < 0 or x >= _map_width or y < 0 or y >= _map_height:
		return -1
	return y * _map_width + x

func _refresh_visibility(signature: PackedInt32Array = PackedInt32Array()) -> void: 
	if _chunk_manager == null: 
		return

	if signature.is_empty():
		signature = _collect_source_signature()
	var next_visible: Dictionary = {}
	for i in range(0, signature.size(), 3):
		_reveal_into(next_visible, Vector2i(signature[i], signature[i + 1]), signature[i + 2])

	var changed_bounds: Rect2i = _changed_visibility_bounds(_visible, next_visible)

	var bounds: Rect2i = _chunk_manager.map_grid_bounds()
	if _visibility_image == null or _mask_size != bounds.size or _mask_origin != bounds.position:
		_init_mask_images(bounds)

	# 1. Revert visibility on cells that are no longer visible
	for cell in _visible:
		if not next_visible.has(cell):
			_write_visibility_pixel(cell as Vector2i, false, 0.0)

	# 2. Write new visibility values
	for cell in next_visible:
		var strength: float = float(next_visible[cell])
		_write_visibility_pixel(cell as Vector2i, true, strength)

	_visible = next_visible
	var prev_explored_size: int = _explored.size()
	for key in _visible:
		_explored[key] = true

	if _explored.size() != prev_explored_size:
		_light_dirty = true
		_explored_cells_dirty = true

	_last_source_signature = signature
	_visibility_dirty = false
	
	if changed_bounds.size != Vector2i.ZERO:
		_light_dirty = true
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
			var radius: int = worker.sight_radius() if worker.has_method("sight_radius") else WORKER_SIGHT_RADIUS 
			out.append(radius) 
			
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
	for key in next: 
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
			
	for key in previous: 
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
	var map_bounds := _chunk_manager.map_grid_bounds()
	
	# Clamp parameters locally to bypass boundary checks inside loop
	var min_y := maxi(center.y - radius, map_bounds.position.y)
	var max_y := mini(center.y + radius, map_bounds.position.y + map_bounds.size.y - 1)
	var min_x := maxi(center.x - radius, map_bounds.position.x)
	var max_x := mini(center.x + radius, map_bounds.position.x + map_bounds.size.x - 1)
	
	var inv_radius: float = 1.0 / float(radius)
	
	for y in range(min_y, max_y + 1): 
		var dy: int = y - center.y
		var dy2: int = dy * dy
		for x in range(min_x, max_x + 1): 
			var dx: int = x - center.x
			var dist2: int = dx * dx + dy2
			if dist2 > r2: 
				continue 
				
			var g := Vector2i(x, y)
			if not LineOfSight.has_los(_chunk_manager, center, g): 
				continue 
				
			var dist: float = sqrt(float(dist2)) 
			var strength: float = clampf(1.0 - pow(dist * inv_radius, 1.85), 0.08, 1.0) 
			target[g] = maxf(float(target.get(g, 0.0)), strength)

func _init_mask_images(bounds: Rect2i) -> void: 
	_mask_origin = bounds.position 
	_mask_size = Vector2i(maxi(1, bounds.size.x), maxi(1, bounds.size.y))
	
	_map_width = _mask_size.x
	_map_height = _mask_size.y
	_map_origin = _mask_origin
	
	var total_cells := _map_width * _map_height
	_explored_flat.resize(total_cells)
	_explored_flat.fill(0)
	
	_visible_flat.resize(total_cells)
	_visible_flat.fill(0.0)
	
	_lit_memory_flat.resize(total_cells)
	_lit_memory_flat.fill(0.0)

	_visibility_image = Image.create(_mask_size.x, _mask_size.y, false, Image.FORMAT_RGBA8) 
	_visibility_image.fill(Color(0.0, 0.0, 0.0, 1.0)) 

	_light_image = Image.create(_mask_size.x, _mask_size.y, false, Image.FORMAT_RGBA8) 
	_light_image.fill(Color(0.0, 0.0, 0.0, 0.0)) 

	# Sync current state into both image textures and optimization caches
	for cell in _explored: 
		var idx := _grid_to_index(cell as Vector2i)
		if idx != -1:
			_explored_flat[idx] = 1
		_write_visibility_pixel(cell as Vector2i, false, 0.0) 
		
	for cell in _visible: 
		var strength: float = float(_visible[cell]) 
		var idx := _grid_to_index(cell as Vector2i)
		if idx != -1:
			_visible_flat[idx] = strength
			_explored_flat[idx] = 1
		_write_visibility_pixel(cell as Vector2i, true, strength)

	if _visibility_mask_texture == null or _visibility_mask_texture.get_width() != _mask_size.x or _visibility_mask_texture.get_height() != _mask_size.y: 
		_visibility_mask_texture = ImageTexture.create_from_image(_visibility_image) 
	else: 
		_visibility_mask_texture.update(_visibility_image)

	if _light_mask_texture == null or _light_mask_texture.get_width() != _mask_size.x or _light_mask_texture.get_height() != _mask_size.y: 
		_light_mask_texture = ImageTexture.create_from_image(_light_image) 
	else: 
		_light_mask_texture.update(_light_image)

	_light_dirty = true

func _write_visibility_pixel(cell: Vector2i, is_vis: bool, strength: float) -> void: 
	var x: int = cell.x - _mask_origin.x 
	var y: int = cell.y - _mask_origin.y 
	if x < 0 or x >= _mask_size.x or y < 0 or y >= _mask_size.y: 
		return

	var r: float = 1.0 
	var g: float = strength if is_vis else 0.0 
	var b: float = strength if is_vis else 0.0 
	_visibility_image.set_pixel(x, y, Color(r, g, b, 1.0))
	
	var idx := y * _map_width + x
	_visible_flat[idx] = strength if is_vis else 0.0
	if is_vis:
		_explored_flat[idx] = 1

func _rebuild_mask_textures() -> void: 
	if _chunk_manager == null: 
		return 
	var bounds: Rect2i = _chunk_manager.map_grid_bounds()

	if _visibility_image == null or _mask_size != bounds.size or _mask_origin != bounds.position: 
		_init_mask_images(bounds)

	if _light_dirty: 
		_rebuild_light_image(bounds) 
		_light_dirty = false 
		_light_mask_texture.update(_light_image)

	_visibility_mask_texture.update(_visibility_image)

func _rebuild_light_image(bounds: Rect2i) -> void: 
	_lit_memory.clear() 
	_light_image.fill(Color(0.0, 0.0, 0.0, 0.0)) 
	_lit_memory_flat.fill(0.0)

	if _structure_manager == null or not _structure_manager.has_method("visual_light_sources"): 
		return 
		
	var sources: Array = _structure_manager.call("visual_light_sources") as Array 
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
			
			var img_y: int = y - _mask_origin.y
			var row_offset: int = img_y * _map_width
			
			for x in range(center.x - radius, center.x + radius + 1): 
				if x < bx0 or x >= bx1: 
					continue 
				
				var img_x: int = x - _mask_origin.x
				var idx: int = row_offset + img_x
				
				# Fast flat array check instead of dictionary hash
				if _explored_flat[idx] == 0: 
					continue 
					
				var dx: int = x - center.x 
				var dy: int = y - center.y 
				var dist2: int = dx * dx + dy * dy 
				if dist2 > r2: 
					continue 
					
				var g := Vector2i(x, y) 
				if not LineOfSight.has_los(_chunk_manager, center, g): 
					continue 
					
				var dist: float = sqrt(float(dist2)) 
				var falloff: float = pow(maxf(0.0, 1.0 - dist * inv_r), 1.65) * intensity 
				_lit_memory[g] = maxf(float(_lit_memory.get(g, 0.0)), falloff) 
				_lit_memory_flat[idx] = maxf(_lit_memory_flat[idx], falloff)

				var base_color: Color = _light_image.get_pixel(img_x, img_y) 
				var lit_color := Color( 
					minf(1.0, base_color.r + color.r * falloff), 
					minf(1.0, base_color.g + color.g * falloff), 
					minf(1.0, base_color.b + color.b * falloff), 
					minf(1.0, base_color.a + falloff) 
				) 
				_light_image.set_pixel(img_x, img_y, lit_color)

func _draw() -> void: 
	if _camera == null or _chunk_manager == null: 
		return 
	
	# Safety guard: exit if the flat arrays have not been allocated/initialized yet
	if _map_width <= 0 or _map_height <= 0 or _visible_flat.is_empty():
		return
		
	var darkness: float = clampf(SettingsManager.overall_darkness, 0.0, 2.0) 
	var bounds: Rect2i = _visible_grid_bounds() 
	
	# Clamp to the actual allocated mask array bounds to prevent out-of-bounds errors
	var lo_x := maxi(bounds.position.x, _mask_origin.x)
	var lo_y := maxi(bounds.position.y, _mask_origin.y)
	var hi_x := mini(bounds.position.x + bounds.size.x, _mask_origin.x + _mask_size.x)
	var hi_y := mini(bounds.position.y + bounds.size.y, _mask_origin.y + _mask_size.y)

	for y in range(lo_y, hi_y): 
		var run_active: bool = false 
		var run_start: int = lo_x 
		var run_color := Color.TRANSPARENT 
		var row_offset: int = (y - _map_origin.y) * _map_width

		for x in range(lo_x, hi_x): 
			var local_x := x - _map_origin.x
			var idx := row_offset + local_x
			
			var sight_strength: float = _visible_flat[idx]
			if sight_strength > 0.0: 
				if sight_strength < 0.92: 
					var edge_alpha: float = (1.0 - sight_strength) * VISIBLE_EDGE_ALPHA * darkness 
					if run_active: 
						_draw_fog_run(run_start, x, y, run_color) 
						run_active = false 
					_draw_fog_run(x, x + 1, y, Color(0.0, 0.0, 0.0, edge_alpha)) 
				else:
					if run_active: 
						_draw_fog_run(run_start, x, y, run_color) 
						run_active = false 
				continue 
				
			var color: Color 
			if _explored_flat[idx] == 1: 
				var lit: float = _lit_memory_flat[idx] 
				var alpha: float = lerpf(MEMORY_COLOR.a, LIT_MEMORY_MIN_ALPHA, smoothstep(0.05, 0.95, lit)) 
				color = Color(MEMORY_COLOR.r, MEMORY_COLOR.g, MEMORY_COLOR.b, clampf(alpha * darkness, 0.0, 1.0)) 
			else: 
				color = UNEXPLORED_COLOR 
				
			if run_active and color == run_color: 
				continue 
				
			if run_active: 
				_draw_fog_run(run_start, x, y, run_color) 
			run_active = true 
			run_start = x 
			run_color = color 
			
		if run_active: 
			_draw_fog_run(run_start, hi_x, y, run_color)

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
