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
@export var static_prop_manager_path: NodePath
@export var fog_of_war_path: NodePath
@export var room_manager_path: NodePath

const TOOLTIP_OFFSET := Vector2(14, 14)
const EDGE_PADDING := 12.0
const HOVER_DWELL_SECONDS: float = 0.5

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _items_root: Node2D
var _workers_root: Node2D
var _structure_manager: StructureManager
var _static_prop_manager: Node
var _fog: FogOfWar
var _room_manager: Node
var _last_grid: Vector2i = Vector2i(2147483647, 2147483647)
var _hover_grid: Vector2i = Vector2i(2147483647, 2147483647)
var _hover_started_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color(0.91, 0.94, 0.92, 1.0))
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	add_theme_stylebox_override("normal", _tooltip_style())
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_job_board = get_node(job_board_path) as JobBoard
	_stockpile_manager = get_node(stockpile_manager_path) as StockpileManager
	_items_root = get_node(items_root_path) as Node2D
	_workers_root = get_node(workers_root_path) as Node2D
	_structure_manager = get_node(structure_manager_path) as StructureManager
	_static_prop_manager = get_node_or_null(static_prop_manager_path)
	_fog = get_node(fog_of_war_path) as FogOfWar
	_room_manager = get_node_or_null(room_manager_path)
	EventBus.visibility_changed.connect(_on_visibility_changed)


func _process(_delta: float) -> void:
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()
	var desired := mouse_screen + TOOLTIP_OFFSET
	var viewport_size := get_viewport_rect().size
	position = Vector2(
		maxf(EDGE_PADDING, minf(desired.x, viewport_size.x - size.x - EDGE_PADDING)),
		maxf(EDGE_PADDING, minf(desired.y, viewport_size.y - size.y - EDGE_PADDING)),
	)
	var grid: Vector2i = _world_to_grid(_camera.get_global_mouse_position())
	if grid != _hover_grid:
		_hover_grid = grid
		_hover_started_msec = Time.get_ticks_msec()
		_last_grid = Vector2i(2147483647, 2147483647)
		visible = false
		return
	var hover_seconds: float = float(Time.get_ticks_msec() - _hover_started_msec) / 1000.0
	if hover_seconds < HOVER_DWELL_SECONDS:
		visible = false
		return
	if grid == _last_grid and visible:
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
		if _structure_manager.has_method("scrap_rewards_text_at"):
			var scrap_rewards: String = _structure_manager.call("scrap_rewards_text_at", grid) as String
			if not scrap_rewards.is_empty():
				lines.append("Scrap yields: " + scrap_rewards)
	elif _static_prop_manager != null:
		var prop_name: String = ""
		if _static_prop_manager.has_method("prop_name_at"):
			prop_name = _static_prop_manager.call("prop_name_at", grid) as String
		if not prop_name.is_empty():
			lines.append("Object: " + prop_name)
			var rewards: String = ""
			if _static_prop_manager.has_method("mine_rewards_text_at"):
				rewards = _static_prop_manager.call("mine_rewards_text_at", grid) as String
			if not rewards.is_empty():
				lines.append("Mine yields: " + rewards)
	var item_line: String = _item_line_at(grid)
	if not item_line.is_empty():
		lines.append(item_line)
	if _worker_at(grid):
		lines.append("Occupant: worker")
	var job_line: String = _job_line_at(grid)
	if not job_line.is_empty():
		lines.append(job_line)
	if _stockpile_manager != null and _stockpile_manager.zone_at(grid) != null:
		var zone: StockpileZone = _stockpile_manager.zone_at(grid)
		lines.append("Stockpile: %d/%d" % [zone.stored_count(), zone.capacity()])
	var room_line: String = _room_line_at(grid)
	if not room_line.is_empty():
		lines.append(room_line)
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
			if occupant is Dictionary:
				var reservation := occupant as Dictionary
				var existing: Item = reservation.get(StockpileZone.R_EXISTING) as Item
				if existing != null and is_instance_valid(existing):
					return "Stored: %s x%d (reserved)" % [Item.kind_name(existing.kind), existing.count]
				var reserved_kind: int = int(reservation.get(StockpileZone.R_KIND, -1))
				if reserved_kind >= 0:
					return "Reserved for: " + Item.kind_name(reserved_kind)
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
		var line: String = "Job: build " + BuildBlueprint.display_name(build.blueprint_id)
		line += "\nDelivered: " + build.delivered_items_text()
		var missing: String = build.missing_items_text()
		if missing != "none":
			line += "\nStill needs: " + missing
		line += "\nRemove refund: " + build.refund_items_text()
		return line
	return ""


func _room_line_at(grid: Vector2i) -> String:
	if _room_manager == null or not _room_manager.has_method("room_status_at"):
		return ""
	return _room_manager.call("room_status_at", grid) as String


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


static func _tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.052, 0.06, 0.92)
	style.border_color = Color(0.48, 0.52, 0.56, 0.62)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 7.0
	style.content_margin_top = 5.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 5.0
	return style
