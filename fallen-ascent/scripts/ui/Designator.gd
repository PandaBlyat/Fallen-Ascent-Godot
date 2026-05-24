class_name Designator
extends Node2D
##
## Handles designation input on the colony scene. One mode at a time:
##   - MINE: right-click a wall to queue (or cancel) a mine job.
##   - STOCKPILE: right-drag a rectangle of floor cells to designate storage.
##   - REMOVE_STOCKPILE: right-click a stockpile cell to delete that zone.
##   - BUILD_WALL: right-click a floor cell to queue (or cancel) a build-wall
##     job (consumes 1 scrap when executed).
##
## Hotkeys (set in project.godot): designate_mine, designate_stockpile,
## designate_remove_stockpile, designate_build, cancel_mode. The right mouse
## button is read directly via Input — we don't need a dedicated action since
## drag detection wants raw press/release.
##

signal mode_changed(mode: int)

enum Mode { NONE, MINE, STOCKPILE, REMOVE_STOCKPILE, BUILD_WALL }

const ZONE_PREVIEW_FILL := Color(0.4, 0.85, 0.5, 0.18)
const ZONE_PREVIEW_BORDER := Color(0.4, 0.85, 0.5, 0.6)
const REMOVE_PREVIEW_BORDER := Color(0.95, 0.4, 0.4, 0.8)

@export var camera_path: NodePath
@export var chunk_manager_path: NodePath
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath

var _camera: Camera2D
var _chunk_manager: ChunkManager
var _job_board: JobBoard
var _stockpile_manager: StockpileManager

var _mode: int = Mode.NONE
var _dragging: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
var _drag_end: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_job_board = get_node(job_board_path) as JobBoard
	_stockpile_manager = get_node(stockpile_manager_path) as StockpileManager


func current_mode() -> int:
	return _mode


func mode_label() -> String:
	match _mode:
		Mode.MINE: return "MINE"
		Mode.STOCKPILE: return "STOCKPILE"
		Mode.REMOVE_STOCKPILE: return "REMOVE_STOCKPILE"
		Mode.BUILD_WALL: return "BUILD WALL"
		_: return "-"


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
	if event.is_action_pressed("cancel_mode"):
		if _mode != Mode.NONE:
			_set_mode(Mode.NONE)
			get_viewport().set_input_as_handled()
		return

	if _mode == Mode.NONE:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mb.pressed:
			_on_right_press(mb)
		else:
			_on_right_release(mb)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_drag_end = _world_to_grid(_camera.get_global_mouse_position())
		queue_redraw()


func _on_right_press(_mb: InputEventMouseButton) -> void:
	var grid := _world_to_grid(_camera.get_global_mouse_position())
	match _mode:
		Mode.MINE:
			_apply_mine_click(grid)
		Mode.STOCKPILE:
			_dragging = true
			_drag_start = grid
			_drag_end = grid
			queue_redraw()
		Mode.REMOVE_STOCKPILE:
			_apply_remove_stockpile_click(grid)
		Mode.BUILD_WALL:
			_apply_build_click(grid)


func _on_right_release(_mb: InputEventMouseButton) -> void:
	if _mode != Mode.STOCKPILE or not _dragging:
		return
	_dragging = false
	var cells: Array[Vector2i] = _rect_cells(_drag_start, _drag_end)
	if not cells.is_empty():
		_stockpile_manager.create_zone(cells)
	queue_redraw()


func _apply_mine_click(grid: Vector2i) -> void:
	if _job_board.has_mine_at(grid):
		_job_board.cancel_mine_at(grid)
		return
	if _chunk_manager.get_tile_at(grid) == TerrainGenerator.TILE_WALL:
		_job_board.add_mine_job(grid)


func _apply_build_click(grid: Vector2i) -> void:
	if _job_board.has_build_at(grid):
		_job_board.cancel_build_at(grid)
		return
	# Only buildable on floor — building on debris or void doesn't make sense
	# yet. Also avoid stockpile cells (no UI to remove the zone first).
	if _chunk_manager.get_tile_at(grid) != TerrainGenerator.TILE_FLOOR:
		return
	if _stockpile_manager.zone_at(grid) != null:
		return
	_job_board.add_build_job(grid, Item.Kind.SCRAP)


func _apply_remove_stockpile_click(grid: Vector2i) -> void:
	var zone: StockpileZone = _stockpile_manager.zone_at(grid)
	if zone == null:
		return
	_stockpile_manager.remove_zone(zone)


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
	if not _dragging:
		return
	var lo := Vector2i(mini(_drag_start.x, _drag_end.x), mini(_drag_start.y, _drag_end.y))
	var hi := Vector2i(maxi(_drag_start.x, _drag_end.x), maxi(_drag_start.y, _drag_end.y))
	var origin := Vector2(lo.x * Chunk.TILE_PIXELS, lo.y * Chunk.TILE_PIXELS)
	var size := Vector2(
		(hi.x - lo.x + 1) * Chunk.TILE_PIXELS,
		(hi.y - lo.y + 1) * Chunk.TILE_PIXELS,
	)
	var r := Rect2(origin, size)
	draw_rect(r, ZONE_PREVIEW_FILL)
	draw_rect(r, ZONE_PREVIEW_BORDER, false, 1.0)
