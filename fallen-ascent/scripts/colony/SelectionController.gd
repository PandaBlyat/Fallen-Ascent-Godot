class_name SelectionController
extends Node2D
##
## Worker selection + direct-order layer. Active only when the Designator is
## in Mode.NONE — designation tools take priority. Lifecycle:
##   - Left-click on a worker → select it (or clear selection if missed).
##   - Right-click while a worker is selected → direct order:
##       * wall  → mine
##       * floor (no zone) → move-to (or build if Shift held)
##       * loose item → walk over (auto-haul will pick it up)
##

@export var camera_path: NodePath
@export var workers_root_path: NodePath
@export var chunk_manager_path: NodePath
@export var designator_path: NodePath

const SELECT_RADIUS_PX: float = 10.0

var _camera: Camera2D
var _workers_root: Node2D
var _chunk_manager: ChunkManager
var _designator: Designator
var _selected: Worker = null


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_workers_root = get_node(workers_root_path) as Node2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_designator = get_node(designator_path) as Designator


func selected_worker() -> Worker:
	return _selected


func _unhandled_input(event: InputEvent) -> void:
	# Designation tools take priority.
	if _designator != null and _designator.current_mode() != Designator.Mode.NONE:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click()
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and _selected != null \
			and is_instance_valid(_selected):
		_handle_right_click(mb.shift_pressed)
		get_viewport().set_input_as_handled()


func _handle_left_click() -> void:
	var world_pos: Vector2 = _camera.get_global_mouse_position()
	var pick: Worker = _worker_under(world_pos)
	_select(pick)


func _handle_right_click(shift_held: bool) -> void:
	var world_pos: Vector2 = _camera.get_global_mouse_position()
	var grid: Vector2i = Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)
	var tile: int = _chunk_manager.get_tile_at(grid)
	if tile == TerrainGenerator.TILE_WALL:
		_selected.command_mine(grid)
		return
	if tile == TerrainGenerator.TILE_FLOOR or tile == TerrainGenerator.TILE_DEBRIS:
		if shift_held:
			_selected.command_build(grid)
		else:
			_selected.command_move(grid)


func _worker_under(world_pos: Vector2) -> Worker:
	if _workers_root == null:
		return null
	var best: Worker = null
	var best_d: float = SELECT_RADIUS_PX
	for child in _workers_root.get_children():
		var w := child as Worker
		if w == null:
			continue
		var d: float = (w.position - world_pos).length()
		if d <= best_d:
			best = w
			best_d = d
	return best


func _select(w: Worker) -> void:
	if _selected == w:
		return
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = w
	if _selected != null:
		_selected.set_selected(true)
	EventBus.worker_selected.emit(_selected)
