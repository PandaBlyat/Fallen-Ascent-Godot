class_name Designator
extends Node2D
##
## Handles designation input on the colony scene. One mode at a time:
##   - MINE: right-click mineable wall/service-core cells.
##   - STOCKPILE: right-drag a rectangle of floor cells to designate storage.
##   - REMOVE_STOCKPILE: right-click a stockpile cell to delete that zone.
##   - BUILD_*: right-click a valid footprint to queue/cancel construction.
##

signal mode_changed(mode: int)

enum Mode {
	NONE,
	MINE,
	STOCKPILE,
	REMOVE_STOCKPILE,
	BUILD_WALL,
	BUILD_DOOR,
	BUILD_LIGHT,
	BUILD_EXTRACTOR,
	BUILD_SENSOR,
	BUILD_CHARGE_PAD,
	BUILD_FABRICATOR,
	BUILD_DOCK,
	BUILD_REPAIR_BENCH,
	BUILD_PARTS_LOOM,
	BUILD_MAINTENANCE_DOCK,
	BUILD_CALIBRATION_SHRINE,
}

const ZONE_PREVIEW_FILL := Color(0.4, 0.85, 0.5, 0.18)
const ZONE_PREVIEW_BORDER := Color(0.4, 0.85, 0.5, 0.6)
const ORDER_PREVIEW_FILL := Color(0.85, 0.72, 0.35, 0.16)
const ORDER_PREVIEW_BORDER := Color(0.95, 0.82, 0.45, 0.65)

@export var camera_path: NodePath
@export var chunk_manager_path: NodePath
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath
@export var structure_manager_path: NodePath
@export var fog_of_war_path: NodePath

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _structure_manager: StructureManager
var _fog: FogOfWar

var _mode: int = Mode.NONE
var _dragging: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
var _drag_end: Vector2i = Vector2i.ZERO
var _hover_grid: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_job_board = get_node(job_board_path) as JobBoard
	_stockpile_manager = get_node(stockpile_manager_path) as StockpileManager
	_structure_manager = get_node(structure_manager_path) as StructureManager
	_fog = get_node(fog_of_war_path) as FogOfWar


func current_mode() -> int:
	return _mode


func set_mode(mode: int) -> void:
	_set_mode(mode)


func toggle_mode(mode: int) -> void:
	_set_mode(Mode.NONE if _mode == mode else mode)


func mode_label() -> String:
	match _mode:
		Mode.MINE: return "MINE"
		Mode.STOCKPILE: return "STOCKPILE"
		Mode.REMOVE_STOCKPILE: return "REMOVE_STOCKPILE"
		Mode.BUILD_WALL: return "BUILD WALL"
		Mode.BUILD_DOOR: return "BUILD DOOR"
		Mode.BUILD_LIGHT: return "BUILD LIGHT"
		Mode.BUILD_EXTRACTOR: return "BUILD EXTRACTOR"
		Mode.BUILD_SENSOR: return "BUILD SENSOR"
		Mode.BUILD_CHARGE_PAD: return "BUILD CHARGE PAD"
		Mode.BUILD_FABRICATOR: return "BUILD FABRICATOR"
		Mode.BUILD_DOCK: return "BUILD DOCK"
		Mode.BUILD_REPAIR_BENCH: return "BUILD REPAIR BENCH"
		Mode.BUILD_PARTS_LOOM: return "BUILD PARTS LOOM"
		Mode.BUILD_MAINTENANCE_DOCK: return "BUILD MAINTENANCE DOCK"
		Mode.BUILD_CALIBRATION_SHRINE: return "BUILD CALIBRATION SHRINE"
		_: return "-"


func cancel_active() -> bool:
	if _mode == Mode.NONE:
		return false
	_set_mode(Mode.NONE)
	return true


func _set_mode(m: int) -> void:
	if _mode == m:
		return
	_mode = m
	_dragging = false
	queue_redraw()
	mode_changed.emit(_mode)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("designate_mine"):
		_set_mode(Mode.MINE if _mode != Mode.MINE else Mode.NONE)
		return
	if event.is_action_pressed("designate_stockpile"):
		_set_mode(Mode.STOCKPILE if _mode != Mode.STOCKPILE else Mode.NONE)
		return
	if event.is_action_pressed("designate_remove_stockpile"):
		_set_mode(Mode.REMOVE_STOCKPILE if _mode != Mode.REMOVE_STOCKPILE else Mode.NONE)
		return
	if event.is_action_pressed("designate_build"):
		_set_mode(Mode.BUILD_WALL if _mode != Mode.BUILD_WALL else Mode.NONE)
		return
	if event.is_action_pressed("designate_build_door"):
		_set_mode(Mode.BUILD_DOOR if _mode != Mode.BUILD_DOOR else Mode.NONE)
		return
	if event.is_action_pressed("designate_build_light"):
		_set_mode(Mode.BUILD_LIGHT if _mode != Mode.BUILD_LIGHT else Mode.NONE)
		return
	if event.is_action_pressed("designate_build_extractor"):
		_set_mode(Mode.BUILD_EXTRACTOR if _mode != Mode.BUILD_EXTRACTOR else Mode.NONE)
		return
	if event.is_action_pressed("cancel_mode"):
		if cancel_active():
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_hover_grid = _world_to_grid(_camera.get_global_mouse_position())
		if _dragging:
			_drag_end = _hover_grid
		queue_redraw()

	if _mode == Mode.NONE:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mb.pressed:
			_on_right_press()
		else:
			_on_right_release()
		get_viewport().set_input_as_handled()


func _on_right_press() -> void:
	var grid := _world_to_grid(_camera.get_global_mouse_position())
	match _mode:
		Mode.MINE, Mode.STOCKPILE, Mode.REMOVE_STOCKPILE, \
		Mode.BUILD_WALL, Mode.BUILD_DOOR, Mode.BUILD_LIGHT, Mode.BUILD_EXTRACTOR, \
		Mode.BUILD_SENSOR, Mode.BUILD_CHARGE_PAD, Mode.BUILD_FABRICATOR, \
		Mode.BUILD_DOCK, Mode.BUILD_REPAIR_BENCH, Mode.BUILD_PARTS_LOOM, \
		Mode.BUILD_MAINTENANCE_DOCK, Mode.BUILD_CALIBRATION_SHRINE:
			_dragging = true
			_drag_start = grid
			_drag_end = grid
			queue_redraw()


func _on_right_release() -> void:
	if not _dragging:
		return
	_dragging = false
	var cells: Array[Vector2i] = _rect_cells(_drag_start, _drag_end)
	var blueprint_id: int = _blueprint_for_mode()
	if _fog != null:
		var explored_cells: Array[Vector2i] = []
		for cell in cells:
			if _fog.is_explored(cell):
				explored_cells.append(cell)
		cells = explored_cells
	if not cells.is_empty():
		match _mode:
			Mode.STOCKPILE:
				_stockpile_manager.create_zone(cells)
			Mode.MINE:
				for cell in cells:
					_apply_mine_click(cell)
			Mode.REMOVE_STOCKPILE:
				for cell in cells:
					_apply_remove_stockpile_click(cell)
			_:
				if _is_build_mode():
					var anchors: Array[Vector2i] = cells if blueprint_id == BuildBlueprint.Id.WALL else [_drag_start]
					for cell in anchors:
						_apply_build_click(cell, blueprint_id)
	queue_redraw()


func _apply_mine_click(grid: Vector2i) -> void:
	if _fog != null and not _fog.is_explored(grid):
		return
	if _job_board.has_mine_at(grid):
		_job_board.cancel_mine_at(grid)
		return
	var tile: int = _chunk_manager.get_tile_at(grid)
	if tile == TerrainGenerator.TILE_WALL \
			or tile == TerrainGenerator.TILE_SERVICE_CORE \
			or tile == TerrainGenerator.TILE_RICH_WALL:
		_job_board.add_mine_job(grid)
	elif tile == TerrainGenerator.TILE_RUST:
		_job_board.add_scrape_rust_job(grid)


func _apply_build_click(grid: Vector2i, blueprint_id: int) -> void:
	if _fog != null and not _fog.is_explored(grid):
		return
	if _job_board.has_build_at(grid):
		_job_board.cancel_build_at(grid)
		return
	if _structure_manager == null or not _structure_manager.can_place_blueprint(blueprint_id, grid):
		return
	_job_board.add_build_job(grid, blueprint_id)


func _apply_remove_stockpile_click(grid: Vector2i) -> void:
	if _fog != null and not _fog.is_explored(grid):
		return
	var zone: StockpileZone = _stockpile_manager.zone_at(grid)
	if zone == null:
		return
	_stockpile_manager.remove_zone(zone)


func _blueprint_for_mode() -> int:
	match _mode:
		Mode.BUILD_DOOR:
			return BuildBlueprint.Id.DOOR
		Mode.BUILD_LIGHT:
			return BuildBlueprint.Id.LIGHT
		Mode.BUILD_EXTRACTOR:
			return BuildBlueprint.Id.EXTRACTOR
		Mode.BUILD_SENSOR:
			return BuildBlueprint.Id.SENSOR
		Mode.BUILD_CHARGE_PAD:
			return BuildBlueprint.Id.CHARGE_PAD
		Mode.BUILD_FABRICATOR:
			return BuildBlueprint.Id.FABRICATOR
		Mode.BUILD_DOCK:
			return BuildBlueprint.Id.DOCK
		Mode.BUILD_REPAIR_BENCH:
			return BuildBlueprint.Id.REPAIR_BENCH
		Mode.BUILD_PARTS_LOOM:
			return BuildBlueprint.Id.PARTS_LOOM
		Mode.BUILD_MAINTENANCE_DOCK:
			return BuildBlueprint.Id.MAINTENANCE_DOCK
		Mode.BUILD_CALIBRATION_SHRINE:
			return BuildBlueprint.Id.CALIBRATION_SHRINE
		_:
			return BuildBlueprint.Id.WALL


func _is_build_mode() -> bool:
	return _mode == Mode.BUILD_WALL \
		or _mode == Mode.BUILD_DOOR \
		or _mode == Mode.BUILD_LIGHT \
		or _mode == Mode.BUILD_EXTRACTOR \
		or _mode == Mode.BUILD_SENSOR \
		or _mode == Mode.BUILD_CHARGE_PAD \
		or _mode == Mode.BUILD_FABRICATOR \
		or _mode == Mode.BUILD_DOCK \
		or _mode == Mode.BUILD_REPAIR_BENCH \
		or _mode == Mode.BUILD_PARTS_LOOM \
		or _mode == Mode.BUILD_MAINTENANCE_DOCK \
		or _mode == Mode.BUILD_CALIBRATION_SHRINE


func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)


static func _rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var out: Array[Vector2i] = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out


func _draw() -> void:
	if _dragging:
		var lo := Vector2i(mini(_drag_start.x, _drag_end.x), mini(_drag_start.y, _drag_end.y))
		var hi := Vector2i(maxi(_drag_start.x, _drag_end.x), maxi(_drag_start.y, _drag_end.y))
		var origin := Vector2(lo.x * Chunk.TILE_PIXELS, lo.y * Chunk.TILE_PIXELS)
		var size := Vector2(
			(hi.x - lo.x + 1) * Chunk.TILE_PIXELS,
			(hi.y - lo.y + 1) * Chunk.TILE_PIXELS,
		)
		var r := Rect2(origin, size)
		var fill: Color = ZONE_PREVIEW_FILL if _mode == Mode.STOCKPILE else ORDER_PREVIEW_FILL
		var border: Color = ZONE_PREVIEW_BORDER if _mode == Mode.STOCKPILE else ORDER_PREVIEW_BORDER
		draw_rect(r, fill)
		draw_rect(r, border, false, 1.0)
	if _is_build_mode():
		_draw_build_ghost(_blueprint_for_mode(), _hover_grid)


func _draw_build_ghost(blueprint_id: int, anchor: Vector2i) -> void:
	var valid: bool = _structure_manager != null \
		and _structure_manager.can_place_blueprint(blueprint_id, anchor) \
		and (_fog == null or _fog.is_explored(anchor))
	var fill: Color = BuildBlueprint.ghost_color(blueprint_id) if valid else Color(0.95, 0.2, 0.2, 0.38)
	var border: Color = Color(fill.r, fill.g, fill.b, 0.9)
	for cell in BuildBlueprint.footprint(blueprint_id, anchor):
		var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, fill)
		draw_rect(rect, border, false, 1.0)
