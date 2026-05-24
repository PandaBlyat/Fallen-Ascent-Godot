class_name SelectionController
extends Node2D
##
## Worker selection + direct-order layer. Active only when Designator is NONE.
## Left-click selects one worker; left-drag selects a group. Right-click issues
## direct orders to all selected workers.
##

@export var camera_path: NodePath
@export var workers_root_path: NodePath
@export var chunk_manager_path: NodePath
@export var pathfinder_path: NodePath
@export var designator_path: NodePath
@export var fog_of_war_path: NodePath

const SELECT_RADIUS_PX: float = 10.0
const DRAG_THRESHOLD_PX: float = 6.0
const DRAG_FILL := Color(0.35, 0.65, 1.0, 0.12)
const DRAG_BORDER := Color(0.55, 0.78, 1.0, 0.8)

var _camera: Camera2D
var _workers_root: Node2D
var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _designator: Designator
var _fog: FogOfWar
var _selected: Array[Worker] = []
var _dragging: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO
var _drag_end_screen: Vector2 = Vector2.ZERO
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_end_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_workers_root = get_node(workers_root_path) as Node2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_pathfinder = get_node(pathfinder_path) as Pathfinder
	_designator = get_node(designator_path) as Designator
	_fog = get_node(fog_of_war_path) as FogOfWar


func selected_worker() -> Worker:
	return _selected[0] if not _selected.is_empty() else null


func selected_workers() -> Array[Worker]:
	return _selected.duplicate()


func clear_selection() -> bool:
	if _selected.is_empty():
		return false
	_select_many([])
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _designator != null and _designator.current_mode() != Designator.Mode.NONE:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_drag(mb.position)
			else:
				_finish_drag(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and not _selected.is_empty():
			_handle_right_click(mb.shift_pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_end_screen = mm.position
		_drag_end_world = _camera.get_global_mouse_position()
		queue_redraw()


func _begin_drag(screen_pos: Vector2) -> void:
	_dragging = true
	_drag_start_screen = screen_pos
	_drag_end_screen = screen_pos
	_drag_start_world = _camera.get_global_mouse_position()
	_drag_end_world = _drag_start_world
	queue_redraw()


func _finish_drag(screen_pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	_drag_end_screen = screen_pos
	_drag_end_world = _camera.get_global_mouse_position()
	var is_box: bool = (_drag_end_screen - _drag_start_screen).length() >= DRAG_THRESHOLD_PX
	if is_box:
		_select_many(_workers_in_rect(_drag_start_world, _drag_end_world))
	else:
		_select_many(_worker_under(_drag_end_world))
	queue_redraw()


func _handle_right_click(shift_held: bool) -> void:
	var world_pos: Vector2 = _camera.get_global_mouse_position()
	var grid: Vector2i = Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)
	if _fog != null and not _fog.is_explored(grid):
		return
	var tile: int = _chunk_manager.get_tile_at(grid)
	if tile == TerrainGenerator.TILE_WALL \
			or tile == TerrainGenerator.TILE_SERVICE_CORE \
			or tile == TerrainGenerator.TILE_RICH_WALL:
		var miner: Worker = selected_worker()
		if miner != null and is_instance_valid(miner):
			miner.command_mine(grid)
		return
	if shift_held and _is_walkable_order_tile(tile):
		var builder: Worker = selected_worker()
		if builder != null and is_instance_valid(builder):
			builder.command_build(grid)
		return
	if tile == TerrainGenerator.TILE_OUTLET:
		_command_one_worker_to_charge(grid)
	elif _is_walkable_order_tile(tile):
		_command_group_move(grid)


func _command_one_worker_to_charge(grid: Vector2i) -> void:
	for worker in _selected_by_distance(grid):
		if worker.command_charge(grid):
			return


func _command_group_move(grid: Vector2i) -> void:
	var workers: Array[Worker] = _selected_by_distance(grid)
	var assigned: Dictionary = {}
	for worker in workers:
		var target: Vector2i = _best_group_target_for(worker, grid, assigned)
		if target == Pathfinder.UNREACHABLE:
			continue
		assigned[target] = true
		worker.command_move(target)


func _best_group_target_for(worker: Worker, center: Vector2i, assigned: Dictionary) -> Vector2i:
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_score: int = 0x7fffffff
	for candidate in _formation_candidates(center, _selected.size() + 8):
		if assigned.has(candidate):
			continue
		if _occupied_by_unselected(candidate):
			continue
		if _fog != null and not _fog.is_explored(candidate):
			continue
		if not _chunk_manager.is_walkable(candidate):
			continue
		if candidate != worker.current_grid() and not _pathfinder.has_path(worker.current_grid(), candidate):
			continue
		var worker_dist: int = maxi(
			absi(candidate.x - worker.current_grid().x),
			absi(candidate.y - worker.current_grid().y),
		)
		var center_dist: int = maxi(absi(candidate.x - center.x), absi(candidate.y - center.y))
		var score: int = center_dist * 1000 + worker_dist
		if score < best_score:
			best = candidate
			best_score = score
	return best


func _formation_candidates(center: Vector2i, count_hint: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append(center)
	var max_radius: int = maxi(2, int(ceil(sqrt(float(count_hint)))) + 6)
	for r in range(1, max_radius + 1):
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				if maxi(absi(x - center.x), absi(y - center.y)) != r:
					continue
				out.append(Vector2i(x, y))
	return out


func _selected_by_distance(grid: Vector2i) -> Array[Worker]:
	var workers: Array[Worker] = []
	for worker in _selected.duplicate():
		if worker != null and is_instance_valid(worker):
			workers.append(worker)
	workers.sort_custom(func(a: Worker, b: Worker) -> bool:
		var da: int = maxi(absi(a.current_grid().x - grid.x), absi(a.current_grid().y - grid.y))
		var db: int = maxi(absi(b.current_grid().x - grid.x), absi(b.current_grid().y - grid.y))
		return da < db
	)
	return workers


func _occupied_by_unselected(grid: Vector2i) -> bool:
	for child in _workers_root.get_children():
		var worker := child as Worker
		if worker == null or _selected.has(worker):
			continue
		if worker.current_grid() == grid:
			return true
	return false


static func _is_walkable_order_tile(tile: int) -> bool:
	return tile == TerrainGenerator.TILE_FLOOR \
		or tile == TerrainGenerator.TILE_DEBRIS \
		or tile == TerrainGenerator.TILE_CONDUIT \
		or tile == TerrainGenerator.TILE_RUST


func _worker_under(world_pos: Vector2) -> Array[Worker]:
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
	var out: Array[Worker] = []
	if best != null:
		out.append(best)
	return out


func _workers_in_rect(a: Vector2, b: Vector2) -> Array[Worker]:
	var rect := Rect2(
		Vector2(minf(a.x, b.x), minf(a.y, b.y)),
		Vector2(absf(a.x - b.x), absf(a.y - b.y)),
	)
	var out: Array[Worker] = []
	for child in _workers_root.get_children():
		var worker := child as Worker
		if worker != null and rect.has_point(worker.position):
			out.append(worker)
	return out


func _select_many(workers: Array[Worker]) -> void:
	for worker in _selected:
		if worker != null and is_instance_valid(worker):
			worker.set_selected(false)
	_selected = workers
	for worker in _selected:
		if worker != null and is_instance_valid(worker):
			worker.set_selected(true)
	EventBus.worker_selected.emit(selected_worker())
	EventBus.workers_selected.emit(_selected.duplicate())


func _draw() -> void:
	if not _dragging:
		return
	var is_box: bool = (_drag_end_screen - _drag_start_screen).length() >= DRAG_THRESHOLD_PX
	if not is_box:
		return
	var origin := Vector2(minf(_drag_start_world.x, _drag_end_world.x), minf(_drag_start_world.y, _drag_end_world.y))
	var size := Vector2(absf(_drag_start_world.x - _drag_end_world.x), absf(_drag_start_world.y - _drag_end_world.y))
	var rect := Rect2(origin, size)
	draw_rect(rect, DRAG_FILL)
	draw_rect(rect, DRAG_BORDER, false, 1.0)
