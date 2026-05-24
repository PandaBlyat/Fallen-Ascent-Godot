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
@export var structure_manager_path: NodePath
@export var neutrals_root_path: NodePath
@export var hostiles_root_path: NodePath

const SELECT_RADIUS_PX: float = 10.0
const DRAG_THRESHOLD_PX: float = 6.0
const DRAG_FILL := Color(0.35, 0.65, 1.0, 0.12)
const DRAG_BORDER := Color(0.55, 0.78, 1.0, 0.8)
const ORDER_HIGHLIGHT_SECONDS: float = 1.2
const ORDER_HIGHLIGHT_FILL := Color(1.0, 0.88, 0.25, 0.22)
const ORDER_HIGHLIGHT_BORDER := Color(1.0, 0.92, 0.35, 0.95)
const ATTACK_HOVER_FILL := Color(0.95, 0.25, 0.25, 0.18)
const ATTACK_HOVER_BORDER := Color(1.0, 0.35, 0.30, 0.95)

var _camera: Camera2D
var _workers_root: Node2D
var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _designator: Designator
var _fog: FogOfWar
var _structure_manager: StructureManager
var _neutrals_root: Node2D
var _hostiles_root: Node2D
var _selected: Array[Worker] = []
var _dragging: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO
var _drag_end_screen: Vector2 = Vector2.ZERO
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_end_world: Vector2 = Vector2.ZERO
var _order_highlight_grid: Vector2i = Pathfinder.UNREACHABLE
var _order_highlight_timer: float = 0.0
var _attack_hover_target: Node2D = null


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_workers_root = get_node(workers_root_path) as Node2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_pathfinder = get_node(pathfinder_path) as Pathfinder
	_designator = get_node(designator_path) as Designator
	_fog = get_node(fog_of_war_path) as FogOfWar
	_structure_manager = get_node_or_null(structure_manager_path) as StructureManager
	_neutrals_root = get_node_or_null(neutrals_root_path) as Node2D
	_hostiles_root = get_node_or_null(hostiles_root_path) as Node2D


func _process(delta: float) -> void:
	if _order_highlight_timer <= 0.0:
		return
	_order_highlight_timer = maxf(0.0, _order_highlight_timer - delta)
	if _order_highlight_timer <= 0.0:
		_order_highlight_grid = Pathfinder.UNREACHABLE
	queue_redraw()


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
	# When a designator mode is active, a plain left-click anywhere cancels it.
	if _designator != null and _designator.current_mode() != Designator.Mode.NONE:
		if event is InputEventMouseButton:
			var mb_d := event as InputEventMouseButton
			if mb_d.pressed and mb_d.button_index == MOUSE_BUTTON_LEFT:
				_designator.cancel_active()
				get_viewport().set_input_as_handled()
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
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_drag_end_screen = mm.position
			_drag_end_world = _camera.get_global_mouse_position()
			queue_redraw()
		_update_attack_hover()


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
		EventBus.bot_inspected.emit(null, 0)
	else:
		var workers: Array[Worker] = _worker_under(_drag_end_world)
		if not workers.is_empty():
			_select_many(workers)
			EventBus.structure_selected.emit(-1, Vector2i.ZERO)
			EventBus.bot_inspected.emit(null, 0)
		else:
			var npc: Node2D = _npc_under(_drag_end_world)
			if npc != null:
				_select_many([])
				EventBus.structure_selected.emit(-1, Vector2i.ZERO)
				var faction_id: int = int(npc.call("faction")) if npc.has_method("faction") else 0
				EventBus.bot_inspected.emit(npc, faction_id)
			elif _try_select_structure(_drag_end_world):
				_select_many([])
				EventBus.bot_inspected.emit(null, 0)
			else:
				_select_many([])
				EventBus.structure_selected.emit(-1, Vector2i.ZERO)
				EventBus.bot_inspected.emit(null, 0)
	queue_redraw()


func _handle_right_click(shift_held: bool) -> void:
	var world_pos: Vector2 = _camera.get_global_mouse_position()
	# Attack any hostile/neutral under cursor (multi-bot via stand spreading).
	var attack_target: Node2D = _attackable_under(world_pos)
	if attack_target != null:
		_command_group_attack(attack_target)
		_show_order_highlight(attack_target.call("current_grid") as Vector2i)
		return
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
			_show_order_highlight(grid)
		return
	if tile == TerrainGenerator.TILE_RUST:
		var scraper: Worker = selected_worker()
		if scraper != null and is_instance_valid(scraper):
			scraper.command_scrape_rust(grid)
			_show_order_highlight(grid)
		return
	if shift_held and _is_walkable_order_tile(tile):
		var builder: Worker = selected_worker()
		if builder != null and is_instance_valid(builder):
			builder.command_build(grid)
			_show_order_highlight(grid)
		return
	if tile == TerrainGenerator.TILE_OUTLET:
		if _command_one_worker_to_charge(grid):
			_show_order_highlight(grid)
	elif _is_walkable_order_tile(tile):
		if _command_group_move(grid):
			_show_order_highlight(grid)


func _command_one_worker_to_charge(grid: Vector2i) -> bool:
	for worker in _selected_by_distance(grid):
		if worker.command_charge(grid):
			return true
	return false


func _command_group_move(grid: Vector2i) -> bool:
	var workers: Array[Worker] = _selected_by_distance(grid)
	var assigned: Dictionary = {}
	for worker in workers:
		var target: Vector2i = _best_group_target_for(worker, grid, assigned)
		if target == Pathfinder.UNREACHABLE:
			continue
		if worker.command_move(target):
			assigned[target] = true
	return not assigned.is_empty()


func _show_order_highlight(grid: Vector2i) -> void:
	_order_highlight_grid = grid
	_order_highlight_timer = ORDER_HIGHLIGHT_SECONDS
	queue_redraw()


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
		or tile == TerrainGenerator.TILE_RUST \
		or tile == TerrainGenerator.TILE_TELEPORTER


func _npc_under(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = SELECT_RADIUS_PX
	for root in [_hostiles_root, _neutrals_root]:
		if root == null:
			continue
		for child in root.get_children():
			if not is_instance_valid(child):
				continue
			if child.has_method("is_alive") and not bool(child.call("is_alive")):
				continue
			if not (child is Node2D):
				continue
			var d: float = ((child as Node2D).position - world_pos).length()
			if d <= best_d:
				best = child as Node2D
				best_d = d
	return best


func _hostile_under(world_pos: Vector2) -> Node2D:
	if _hostiles_root == null:
		return null
	var best: Node2D = null
	var best_d: float = SELECT_RADIUS_PX
	for child in _hostiles_root.get_children():
		if not is_instance_valid(child):
			continue
		if child.has_method("is_alive") and not bool(child.call("is_alive")):
			continue
		if not (child is Node2D):
			continue
		if not (child as Node2D).visible:
			continue
		var d: float = ((child as Node2D).position - world_pos).length()
		if d <= best_d:
			best = child as Node2D
			best_d = d
	return best


func _attackable_under(world_pos: Vector2) -> Node2D:
	# Returns the closest hostile OR neutral under the cursor that the player
	# can attack. Hostiles win ties to keep the priority intuitive.
	var best: Node2D = _hostile_under(world_pos)
	if best != null:
		return best
	if _neutrals_root == null:
		return null
	var best_d: float = SELECT_RADIUS_PX
	for child in _neutrals_root.get_children():
		if not is_instance_valid(child):
			continue
		if child.has_method("is_alive") and not bool(child.call("is_alive")):
			continue
		if not (child is Node2D):
			continue
		# Only allow targeting bots the player can see (fog-aware).
		if not (child as Node2D).visible:
			continue
		var d: float = ((child as Node2D).position - world_pos).length()
		if d <= best_d:
			best = child as Node2D
			best_d = d
	return best


func _command_group_attack(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_grid: Vector2i = target.call("current_grid") as Vector2i
	var workers: Array[Worker] = _selected_by_distance(target_grid)
	var assigned_stand: Dictionary = {}
	for worker in workers:
		if worker == null or not is_instance_valid(worker):
			continue
		if not worker.has_method("command_attack"):
			continue
		var stand: Vector2i = _best_attack_stand(worker, target_grid, assigned_stand)
		worker.call("command_attack", target, stand)
		if stand != Pathfinder.UNREACHABLE:
			assigned_stand[stand] = true


func _best_attack_stand(worker: Worker, target_grid: Vector2i, assigned: Dictionary) -> Vector2i:
	# Find the closest unassigned walkable cell adjacent to target_grid.
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var best: Vector2i = Pathfinder.UNREACHABLE
	var best_d: int = 0x7fffffff
	var origin: Vector2i = worker.current_grid()
	for off in OFFSETS:
		var candidate: Vector2i = target_grid + off
		if assigned.has(candidate):
			continue
		if not _chunk_manager.is_walkable(candidate):
			continue
		if _occupied_by_unselected(candidate):
			continue
		if candidate != origin and not _pathfinder.has_path(origin, candidate):
			continue
		var d: int = maxi(absi(candidate.x - origin.x), absi(candidate.y - origin.y))
		if d < best_d:
			best = candidate
			best_d = d
	return best


func _update_attack_hover() -> void:
	if _camera == null:
		return
	var new_target: Node2D = null
	if not _selected.is_empty():
		new_target = _attackable_under(_camera.get_global_mouse_position())
	if new_target != _attack_hover_target:
		_attack_hover_target = new_target
		queue_redraw()


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


func _try_select_structure(world_pos: Vector2) -> bool:
	if _structure_manager == null:
		return false
	var grid := Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)
	if _fog != null and not _fog.is_explored(grid):
		return false
	var structure: Dictionary = _structure_manager.structure_at(grid)
	if structure.is_empty():
		return false
	EventBus.structure_selected.emit(int(structure["id"]), structure["anchor"] as Vector2i)
	return true


func _select_many(workers: Array[Worker]) -> void:
	for worker in _selected:
		if worker != null and is_instance_valid(worker):
			worker.set_selected(false)
	_selected = workers
	for worker in _selected:
		if worker != null and is_instance_valid(worker):
			worker.set_selected(true)
	if _selected.is_empty() and _attack_hover_target != null:
		_attack_hover_target = null
		queue_redraw()
	EventBus.worker_selected.emit(selected_worker())
	EventBus.workers_selected.emit(_selected.duplicate())


func _draw() -> void:
	var designator_idle: bool = _designator == null or _designator.current_mode() == Designator.Mode.NONE
	if designator_idle and _attack_hover_target != null and is_instance_valid(_attack_hover_target):
		var g: Vector2i = _attack_hover_target.call("current_grid") as Vector2i
		var origin := Vector2(g.x * Chunk.TILE_PIXELS, g.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, ATTACK_HOVER_FILL)
		draw_rect(rect, ATTACK_HOVER_BORDER, false, 1.5)
	if _order_highlight_grid != Pathfinder.UNREACHABLE:
		var alpha: float = clampf(_order_highlight_timer / ORDER_HIGHLIGHT_SECONDS, 0.0, 1.0)
		var origin := Vector2(_order_highlight_grid.x * Chunk.TILE_PIXELS, _order_highlight_grid.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, Color(ORDER_HIGHLIGHT_FILL.r, ORDER_HIGHLIGHT_FILL.g, ORDER_HIGHLIGHT_FILL.b, ORDER_HIGHLIGHT_FILL.a * alpha))
		draw_rect(rect, Color(ORDER_HIGHLIGHT_BORDER.r, ORDER_HIGHLIGHT_BORDER.g, ORDER_HIGHLIGHT_BORDER.b, ORDER_HIGHLIGHT_BORDER.a * alpha), false, 1.5)
	if _dragging:
		var is_box: bool = (_drag_end_screen - _drag_start_screen).length() >= DRAG_THRESHOLD_PX
		if not is_box:
			return
		var drag_origin := Vector2(minf(_drag_start_world.x, _drag_end_world.x), minf(_drag_start_world.y, _drag_end_world.y))
		var size := Vector2(absf(_drag_start_world.x - _drag_end_world.x), absf(_drag_start_world.y - _drag_end_world.y))
		var drag_rect := Rect2(drag_origin, size)
		draw_rect(drag_rect, DRAG_FILL)
		draw_rect(drag_rect, DRAG_BORDER, false, 1.0)
