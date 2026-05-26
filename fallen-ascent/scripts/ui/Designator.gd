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
	SCRAPE_BIOMASS,
	STOCKPILE,
	REMOVE_STOCKPILE,
	BUILD_WALL,
	BUILD_DOOR,
	BUILD_EXTRACTOR,
	BUILD_SENSOR,
	BUILD_CHARGE_PAD,
	BUILD_FABRICATOR,
	BUILD_DOCK,
	BUILD_REPAIR_BENCH,
	BUILD_PARTS_LOOM,
	BUILD_MAINTENANCE_DOCK,
	BUILD_MEDITATION_PAD,
	BUILD_SENTIENCE_CRADLE,
	BUILD_FABRICATION_SPOT,
	BUILD_FABRICATOR_ADVANCED,
	PLACE_STORAGE_BIN,
	PLACE_OUTLET_EXTENSION,
	PLACE_RUDIMENTARY_SENSOR,
	PLACE_SMALL_LIGHT_DEVICE,
	PLACE_LARGE_LIGHT_DEVICE,
	DESIGNATE_DOCK_ROOM,
	DESIGNATE_RESEARCH_ROOM,
	DESIGNATE_MECHANIC_ROOM,
	DESIGNATE_WORKSHOP_ROOM,
	REMOVE_ROOM,
	DELETE,
}

const ZONE_PREVIEW_FILL := Color(0.4, 0.85, 0.5, 0.09)
const ZONE_PREVIEW_BORDER := Color(0.4, 0.85, 0.5, 0.40)
const ORDER_PREVIEW_FILL := Color(0.85, 0.72, 0.35, 0.08)
const ORDER_PREVIEW_BORDER := Color(0.95, 0.82, 0.45, 0.40)
const ROOM_PREVIEW_FILL := Color(0.45, 0.62, 0.98, 0.09)
const ROOM_PREVIEW_BORDER := Color(0.45, 0.62, 0.98, 0.45)
const OUTLET_RANGE_COLOR := Color(0.35, 0.78, 1.0, 0.20)
const DELETE_PREVIEW_FILL := Color(0.95, 0.20, 0.20, 0.18)
const DELETE_PREVIEW_BORDER := Color(1.0, 0.32, 0.28, 0.85)

@export var camera_path: NodePath
@export var chunk_manager_path: NodePath
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath
@export var structure_manager_path: NodePath
@export var static_prop_manager_path: NodePath
@export var fog_of_war_path: NodePath
@export var room_manager_path: NodePath

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _structure_manager: StructureManager
var _static_prop_manager: Node
var _fog: FogOfWar
var _room_manager: Node

var _mode: int = Mode.NONE
var _dragging: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
var _drag_end: Vector2i = Vector2i.ZERO
var _hover_grid: Vector2i = Vector2i.ZERO
var _build_rotation: int = 0


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_job_board = get_node(job_board_path) as JobBoard
	_stockpile_manager = get_node(stockpile_manager_path) as StockpileManager
	_structure_manager = get_node(structure_manager_path) as StructureManager
	_static_prop_manager = get_node_or_null(static_prop_manager_path)
	_fog = get_node(fog_of_war_path) as FogOfWar
	_room_manager = get_node_or_null(room_manager_path)


func current_mode() -> int:
	return _mode


func set_mode(mode: int) -> void:
	_set_mode(mode)


func toggle_mode(mode: int) -> void:
	_set_mode(Mode.NONE if _mode == mode else mode)


func mode_label() -> String:
	match _mode:
		Mode.MINE: return "MINE"
		Mode.SCRAPE_BIOMASS: return "SCRAPE BIOMASS"
		Mode.STOCKPILE: return "STOCKPILE"
		Mode.REMOVE_STOCKPILE: return "REMOVE_STOCKPILE"
		Mode.BUILD_WALL: return "BUILD WALL"
		Mode.BUILD_DOOR: return "BUILD DOOR"
		Mode.BUILD_EXTRACTOR: return "BUILD EXTRACTOR"
		Mode.BUILD_SENSOR: return "BUILD SENSOR"
		Mode.BUILD_CHARGE_PAD: return "BUILD CHARGE"
		Mode.BUILD_FABRICATOR: return "BUILD CRAFTING BENCH"
		Mode.BUILD_DOCK: return "BUILD DOCK BED"
		Mode.BUILD_REPAIR_BENCH: return "BUILD REPAIR BENCH"
		Mode.BUILD_PARTS_LOOM: return "BUILD ASSEMBLER PRESS"
		Mode.BUILD_MAINTENANCE_DOCK: return "BUILD MECHANIC DOCK"
		Mode.BUILD_MEDITATION_PAD: return "BUILD RESEARCH BENCH"
		Mode.BUILD_SENTIENCE_CRADLE: return "BUILD REPLICATION CRADLE"
		Mode.BUILD_FABRICATION_SPOT: return "BUILD CRAFTING SPOT"
		Mode.BUILD_FABRICATOR_ADVANCED: return "BUILD FABRICATOR"
		Mode.PLACE_STORAGE_BIN: return "PLACE STORAGE BIN"
		Mode.PLACE_OUTLET_EXTENSION: return "PLACE OUTLET EXTENSION"
		Mode.PLACE_RUDIMENTARY_SENSOR: return "PLACE RUDIMENTARY SENSOR"
		Mode.PLACE_SMALL_LIGHT_DEVICE: return "PLACE SMALL LIGHT"
		Mode.PLACE_LARGE_LIGHT_DEVICE: return "PLACE LARGE LIGHT"
		Mode.DESIGNATE_DOCK_ROOM: return "DOCK ROOM"
		Mode.DESIGNATE_RESEARCH_ROOM: return "RESEARCH ROOM"
		Mode.DESIGNATE_MECHANIC_ROOM: return "MECHANIC ROOM"
		Mode.DESIGNATE_WORKSHOP_ROOM: return "WORKSHOP ROOM"
		Mode.REMOVE_ROOM: return "REMOVE ROOM"
		Mode.DELETE: return "DELETE"
		_: return "-"


func cancel_active() -> bool:
	if _mode == Mode.NONE:
		return false
	_dragging = false
	_set_mode(Mode.NONE)
	return true


func is_active() -> bool:
	return _mode != Mode.NONE


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
	if event.is_action_pressed("designate_build_extractor"):
		_set_mode(Mode.BUILD_EXTRACTOR if _mode != Mode.BUILD_EXTRACTOR else Mode.NONE)
		return
	if event.is_action_pressed("cancel_mode"):
		if cancel_active():
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_R and _is_build_mode():
			_build_rotation = posmod(_build_rotation + 1, 4)
			queue_redraw()
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
		# The secondary mouse button drives every mode (paint, designate,
		# place). The primary button is reserved for SelectionController and
		# cancels the active designation mode. Which physical button is
		# "primary" depends on the swap-mouse-buttons setting.
		if mb.button_index == SettingsManager.secondary_mouse_button():
			if mb.pressed:
				_on_right_press()
			else:
				_on_right_release()
			get_viewport().set_input_as_handled()


func _on_right_press() -> void:
	var grid := _world_to_grid(_camera.get_global_mouse_position())
	match _mode:
		Mode.MINE, Mode.SCRAPE_BIOMASS, Mode.STOCKPILE, Mode.REMOVE_STOCKPILE, \
		Mode.BUILD_WALL, Mode.BUILD_DOOR, Mode.BUILD_EXTRACTOR, \
		Mode.BUILD_SENSOR, Mode.BUILD_CHARGE_PAD, Mode.BUILD_FABRICATOR, \
		Mode.BUILD_DOCK, Mode.BUILD_REPAIR_BENCH, Mode.BUILD_PARTS_LOOM, \
		Mode.BUILD_MAINTENANCE_DOCK, \
		Mode.BUILD_MEDITATION_PAD, Mode.BUILD_SENTIENCE_CRADLE, Mode.BUILD_FABRICATION_SPOT, \
		Mode.BUILD_FABRICATOR_ADVANCED, \
		Mode.PLACE_STORAGE_BIN, Mode.PLACE_OUTLET_EXTENSION, Mode.PLACE_RUDIMENTARY_SENSOR, \
		Mode.PLACE_SMALL_LIGHT_DEVICE, Mode.PLACE_LARGE_LIGHT_DEVICE, \
		Mode.DESIGNATE_DOCK_ROOM, Mode.DESIGNATE_RESEARCH_ROOM, \
		Mode.DESIGNATE_MECHANIC_ROOM, Mode.DESIGNATE_WORKSHOP_ROOM, Mode.REMOVE_ROOM, \
		Mode.DELETE:
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
			Mode.SCRAPE_BIOMASS:
				for cell in cells:
					_apply_scrape_biomass_click(cell)
			Mode.REMOVE_STOCKPILE:
				for cell in cells:
					_apply_remove_stockpile_click(cell)
			Mode.DESIGNATE_DOCK_ROOM:
				_apply_dock_room(cells)
			Mode.DESIGNATE_RESEARCH_ROOM:
				_apply_research_room(cells)
			Mode.DESIGNATE_MECHANIC_ROOM:
				_apply_mechanic_room(cells)
			Mode.DESIGNATE_WORKSHOP_ROOM:
				_apply_workshop_room(cells)
			Mode.REMOVE_ROOM:
				for cell in cells:
					_apply_remove_room(cell)
			Mode.DELETE:
				for cell in cells:
					_apply_delete_click(cell)
			_:
				if _is_build_mode():
					var anchors: Array[Vector2i] = []
					if blueprint_id == BuildBlueprint.Id.WALL:
						anchors = cells
					else:
						anchors.append(_drag_start)
					for cell in anchors:
						_apply_build_click(cell, blueprint_id)
	queue_redraw()


func _apply_mine_click(grid: Vector2i) -> void:
	if _fog != null and not _fog.is_explored(grid):
		return
	if _job_board.has_mine_at(grid):
		_job_board.cancel_mine_at(grid)
		return
	if _static_prop_manager != null \
			and _static_prop_manager.has_method("has_mineable_prop") \
			and bool(_static_prop_manager.call("has_mineable_prop", grid)):
		_job_board.add_mine_job(grid)
		return
	var tile: int = _chunk_manager.get_tile_at(grid)
	if tile == TerrainGenerator.TILE_WALL \
			or tile == TerrainGenerator.TILE_SERVICE_CORE \
			or tile == TerrainGenerator.TILE_RICH_WALL:
		_job_board.add_mine_job(grid)
	elif tile == TerrainGenerator.TILE_RUST:
		_job_board.add_scrape_rust_job(grid)


func _apply_scrape_biomass_click(grid: Vector2i) -> void:
	if _fog != null and not _fog.is_explored(grid):
		return
	if not _chunk_manager.has_grass(grid):
		return
	if _job_board.has_scrape_biomass_at(grid):
		_job_board.cancel_scrape_biomass_at(grid)
		return
	_job_board.add_scrape_biomass_job(grid)


func _apply_build_click(grid: Vector2i, blueprint_id: int) -> void:
	if _fog != null and not _fog.is_explored(grid):
		return
	if _job_board.has_build_at(grid):
		_job_board.cancel_build_at(grid)
		return
	if _structure_manager == null or not _structure_manager.can_place_blueprint(blueprint_id, grid, _build_rotation):
		return
	_job_board.add_build_job(grid, blueprint_id, _build_rotation)


func _apply_remove_stockpile_click(grid: Vector2i) -> void:
	if _fog != null and not _fog.is_explored(grid):
		return
	var zone: StockpileZone = _stockpile_manager.zone_at(grid)
	if zone == null:
		return
	_stockpile_manager.remove_zone(zone)


func _apply_dock_room(cells: Array[Vector2i]) -> void:
	if _room_manager == null or not _room_manager.has_method("create_dock_room"):
		return
	_room_manager.call("create_dock_room", cells)


func _apply_research_room(cells: Array[Vector2i]) -> void:
	if _room_manager == null or not _room_manager.has_method("create_research_room"):
		return
	_room_manager.call("create_research_room", cells)


func _apply_mechanic_room(cells: Array[Vector2i]) -> void:
	if _room_manager == null or not _room_manager.has_method("create_mechanic_room"):
		return
	_room_manager.call("create_mechanic_room", cells)


func _apply_workshop_room(cells: Array[Vector2i]) -> void:
	if _room_manager == null or not _room_manager.has_method("create_workshop_room"):
		return
	_room_manager.call("create_workshop_room", cells)


func _apply_delete_click(grid: Vector2i) -> void:
	# Global delete tool: tries each player-affecting thing under the cursor
	# in priority order (build job > placed structure > stockpile zone > room
	# designation > mineable prop > scrappable world light). Refund handling
	# lives in the destination managers.
	if _fog != null and not _fog.is_explored(grid):
		return
	if _job_board != null and _job_board.has_build_at(grid):
		_job_board.cancel_build_at(grid)
		return
	if _structure_manager != null and _structure_manager.has_method("delete_structure_at"):
		var removed: bool = bool(_structure_manager.call("delete_structure_at", grid))
		if removed:
			return
	if _stockpile_manager != null:
		var zone: StockpileZone = _stockpile_manager.zone_at(grid)
		if zone != null:
			_stockpile_manager.remove_zone(zone)
			return
	if _room_manager != null and _room_manager.has_method("remove_room_at"):
		_room_manager.call("remove_room_at", grid)
		return
	if _job_board != null and _job_board.has_mine_at(grid):
		_job_board.cancel_mine_at(grid)
		return
	if _job_board != null and _job_board.has_scrape_biomass_at(grid):
		_job_board.cancel_scrape_biomass_at(grid)
		return


func _apply_remove_room(grid: Vector2i) -> void:
	if _room_manager == null or not _room_manager.has_method("remove_room_at"):
		return
	_room_manager.call("remove_room_at", grid)


func _blueprint_for_mode() -> int:
	match _mode:
		Mode.BUILD_DOOR:
			return BuildBlueprint.Id.DOOR
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
		Mode.BUILD_MEDITATION_PAD:
			return BuildBlueprint.Id.MEDITATION_PAD
		Mode.BUILD_SENTIENCE_CRADLE:
			return BuildBlueprint.Id.SENTIENCE_CRADLE
		Mode.BUILD_FABRICATION_SPOT:
			return BuildBlueprint.Id.FABRICATION_SPOT
		Mode.BUILD_FABRICATOR_ADVANCED:
			return BuildBlueprint.Id.FABRICATOR_ADVANCED
		Mode.PLACE_STORAGE_BIN:
			return BuildBlueprint.Id.STORAGE_BIN
		Mode.PLACE_OUTLET_EXTENSION:
			return BuildBlueprint.Id.OUTLET_EXTENSION
		Mode.PLACE_RUDIMENTARY_SENSOR:
			return BuildBlueprint.Id.RUDIMENTARY_SENSOR
		Mode.PLACE_SMALL_LIGHT_DEVICE:
			return BuildBlueprint.Id.SMALL_LIGHT_DEVICE
		Mode.PLACE_LARGE_LIGHT_DEVICE:
			return BuildBlueprint.Id.LARGE_LIGHT_DEVICE
		_:
			return BuildBlueprint.Id.WALL


func _is_build_mode() -> bool:
	return _mode == Mode.BUILD_WALL \
		or _mode == Mode.BUILD_DOOR \
		or _mode == Mode.BUILD_EXTRACTOR \
		or _mode == Mode.BUILD_SENSOR \
		or _mode == Mode.BUILD_CHARGE_PAD \
		or _mode == Mode.BUILD_FABRICATOR \
		or _mode == Mode.BUILD_DOCK \
		or _mode == Mode.BUILD_REPAIR_BENCH \
		or _mode == Mode.BUILD_PARTS_LOOM \
		or _mode == Mode.BUILD_MAINTENANCE_DOCK \
		or _mode == Mode.BUILD_MEDITATION_PAD \
		or _mode == Mode.BUILD_SENTIENCE_CRADLE \
		or _mode == Mode.BUILD_FABRICATION_SPOT \
		or _mode == Mode.BUILD_FABRICATOR_ADVANCED \
		or _is_place_mode()


func _is_place_mode() -> bool:
	return _mode == Mode.PLACE_STORAGE_BIN \
		or _mode == Mode.PLACE_OUTLET_EXTENSION \
		or _mode == Mode.PLACE_RUDIMENTARY_SENSOR \
		or _mode == Mode.PLACE_SMALL_LIGHT_DEVICE \
		or _mode == Mode.PLACE_LARGE_LIGHT_DEVICE \
		or _mode == Mode.BUILD_EXTRACTOR \
		or _mode == Mode.BUILD_SENSOR \
		or _mode == Mode.BUILD_CHARGE_PAD \
		or _mode == Mode.BUILD_FABRICATOR \
		or _mode == Mode.BUILD_DOCK \
		or _mode == Mode.BUILD_REPAIR_BENCH \
		or _mode == Mode.BUILD_PARTS_LOOM \
		or _mode == Mode.BUILD_MAINTENANCE_DOCK \
		or _mode == Mode.BUILD_MEDITATION_PAD \
		or _mode == Mode.BUILD_SENTIENCE_CRADLE \
		or _mode == Mode.BUILD_FABRICATION_SPOT \
		or _mode == Mode.BUILD_FABRICATOR_ADVANCED


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
		var fill: Color = ORDER_PREVIEW_FILL
		var border: Color = ORDER_PREVIEW_BORDER
		if _mode == Mode.STOCKPILE:
			fill = ZONE_PREVIEW_FILL
			border = ZONE_PREVIEW_BORDER
		elif _mode == Mode.DESIGNATE_DOCK_ROOM \
				or _mode == Mode.DESIGNATE_RESEARCH_ROOM \
				or _mode == Mode.DESIGNATE_MECHANIC_ROOM \
				or _mode == Mode.DESIGNATE_WORKSHOP_ROOM:
			fill = ROOM_PREVIEW_FILL
			border = ROOM_PREVIEW_BORDER
		elif _mode == Mode.DELETE or _mode == Mode.REMOVE_STOCKPILE or _mode == Mode.REMOVE_ROOM:
			fill = DELETE_PREVIEW_FILL
			border = DELETE_PREVIEW_BORDER
		draw_rect(r, fill)
		draw_rect(r, border, false, 0.8)
	if _mode == Mode.DELETE:
		# Hover indicator outside of dragging — a single red cell under the cursor.
		var origin := Vector2(_hover_grid.x * Chunk.TILE_PIXELS, _hover_grid.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, DELETE_PREVIEW_FILL)
		draw_rect(rect, DELETE_PREVIEW_BORDER, false, 1.2)
	if _is_build_mode():
		_draw_build_ghost(_blueprint_for_mode(), _hover_grid)


func _draw_build_ghost(blueprint_id: int, anchor: Vector2i) -> void:
	var valid: bool = _structure_manager != null \
		and _structure_manager.can_place_blueprint(blueprint_id, anchor, _build_rotation) \
		and (_fog == null or _fog.is_explored(anchor))
	var outlet_range: int = BuildBlueprint.outlet_range(blueprint_id)
	if outlet_range > 0:
		_draw_outlet_ranges(outlet_range)
	var raw_fill: Color = BuildBlueprint.ghost_color(blueprint_id) if valid else Color(0.95, 0.2, 0.2, 0.38)
	if outlet_range > 0 and valid:
		raw_fill = Color(0.25, 0.95, 0.35, 0.45)
	var fill: Color = Color(raw_fill.r, raw_fill.g, raw_fill.b, raw_fill.a * 0.55)
	var border: Color = Color(raw_fill.r, raw_fill.g, raw_fill.b, 0.55)
	for cell in BuildBlueprint.footprint(blueprint_id, anchor, _build_rotation):
		var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, fill)
		draw_rect(rect, border, false, 0.8)


func _draw_outlet_ranges(tile_radius: int) -> void:
	if _chunk_manager == null or _camera == null:
		return
	var radius_px: float = tile_radius * Chunk.TILE_PIXELS
	var view_size: Vector2 = get_viewport_rect().size / _camera.zoom.x
	var view_rect := Rect2(_camera.get_screen_center_position() - view_size * 0.5, view_size).grow(radius_px)
	for outlet in _chunk_manager.outlet_cells():
		var outlet_cell: Vector2i = outlet as Vector2i
		var center: Vector2 = Chunk.grid_to_pixel_center(outlet_cell)
		if not view_rect.has_point(center):
			continue
		_draw_dashed_circle(center, radius_px, OUTLET_RANGE_COLOR, 1.0)


func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments: int = 64
	for i in range(0, segments, 2):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		draw_arc(center, radius, a0, a1, 4, color, width)
