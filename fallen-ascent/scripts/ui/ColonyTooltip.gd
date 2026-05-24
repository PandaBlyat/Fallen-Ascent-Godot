extends Label
##
## Mouse-follow tooltip for colony grid cells. Reads only when hovered cell
## changes, or visibility changes.
##

@export var camera_path: NodePath
@export var chunk_manager_path: NodePath
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath
@export var items_root_path: NodePath
@export var workers_root_path: NodePath
@export var structure_manager_path: NodePath
@export var fog_of_war_path: NodePath

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _items_root: Node2D
var _workers_root: Node2D
var _structure_manager: StructureManager
var _fog: FogOfWar
var _last_grid: Vector2i = Vector2i(2147483647, 2147483647)


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_job_board = get_node(job_board_path) as JobBoard
	_stockpile_manager = get_node(stockpile_manager_path) as StockpileManager
	_items_root = get_node(items_root_path) as Node2D
	_workers_root = get_node(workers_root_path) as Node2D
	_structure_manager = get_node(structure_manager_path) as StructureManager
	_fog = get_node(fog_of_war_path) as FogOfWar
	EventBus.visibility_changed.connect(_on_visibility_changed)


func _process(_delta: float) -> void:
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()
	position = mouse_screen + Vector2(16, 16)
	var grid: Vector2i = _world_to_grid(_camera.get_global_mouse_position())
	if grid == _last_grid:
		return
	_last_grid = grid
	_refresh(grid)


func _on_visibility_changed(_bounds: Rect2i) -> void:
	_refresh(_last_grid)


func _refresh(grid: Vector2i) -> void:
	if not _chunk_manager.is_grid_in_map(grid):
		visible = false
		return
	visible = true
	if _fog != null and not _fog.is_explored(grid):
		text = "Unknown"
		return
	var lines: Array[String] = []
	lines.append("Tile: " + TerrainGenerator.tile_name(_chunk_manager.get_tile_at(grid)))
	var structure_name: String = _structure_manager.structure_name_at(grid) if _structure_manager != null else ""
	if not structure_name.is_empty():
		lines.append("Object: " + structure_name)
	var item_line: String = _item_line_at(grid)
	if not item_line.is_empty():
		lines.append(item_line)
	if _worker_at(grid):
		lines.append("Occupant: worker")
	var job_line: String = _job_line_at(grid)
	if not job_line.is_empty():
		lines.append(job_line)
	if _stockpile_manager != null and _stockpile_manager.zone_at(grid) != null:
		lines.append("Stockpile")
	text = _join_lines(lines)


func _item_line_at(grid: Vector2i) -> String:
	if _items_root != null:
		for child in _items_root.get_children():
			var item := child as Item
			if item != null and item.get_grid() == grid:
				return "Item: %s x%d" % [Item.kind_name(item.kind), item.count]
	if _stockpile_manager != null:
		var zone: StockpileZone = _stockpile_manager.zone_at(grid)
		if zone != null:
			var occupant: Variant = zone.occupant.get(grid)
			if occupant is Item:
				var stored := occupant as Item
				return "Stored: %s x%d" % [Item.kind_name(stored.kind), stored.count]
	return ""


func _worker_at(grid: Vector2i) -> bool:
	if _workers_root == null:
		return false
	for child in _workers_root.get_children():
		var worker := child as Worker
		if worker != null and worker.current_grid() == grid:
			return true
	return false


func _job_line_at(grid: Vector2i) -> String:
	if _job_board == null:
		return ""
	if _job_board.has_mine_at(grid):
		return "Job: mine"
	var build: BuildJob = _job_board.build_job_at(grid)
	if build != null:
		return "Job: build " + BuildBlueprint.display_name(build.blueprint_id)
	return ""


static func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)


static func _join_lines(lines: Array[String]) -> String:
	var out: String = ""
	for line in lines:
		if not out.is_empty():
			out += "\n"
		out += line
	return out
