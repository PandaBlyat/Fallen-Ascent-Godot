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
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath
@export var fog_of_war_path: NodePath
@export var structure_manager_path: NodePath
@export var static_prop_manager_path: NodePath
@export var neutrals_root_path: NodePath
@export var hostiles_root_path: NodePath

const SELECT_RADIUS_PX: float = 10.0
const DRAG_THRESHOLD_PX: float = 6.0
const DRAG_FILL := Color(0.40, 0.78, 1.0, 0.22)
const DRAG_BORDER := Color(0.75, 0.92, 1.0, 0.95)
const DRAG_BORDER_PX: float = 2.0
const ORDER_HIGHLIGHT_SECONDS: float = 1.2
const ORDER_HIGHLIGHT_FILL := Color(1.0, 0.88, 0.25, 0.10)
const ORDER_HIGHLIGHT_BORDER := Color(1.0, 0.92, 0.35, 0.55)
const ATTACK_HOVER_FILL := Color(0.95, 0.25, 0.25, 0.08)
const ATTACK_HOVER_BORDER := Color(1.0, 0.35, 0.30, 0.55)
const HOVER_FILL := Color(0.35, 0.88, 1.0, 0.07)
const HOVER_BORDER := Color(0.52, 0.94, 1.0, 0.62)
const PATH_PREVIEW_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const ORDER_FAIL_SECONDS: float = 1.2
const ORDER_FAIL_FILL := Color(1.0, 0.12, 0.12, 0.10)
const ORDER_FAIL_BORDER := Color(1.0, 0.22, 0.18, 0.55)
const HIGHLIGHT_BORDER_PX: float = 1.0
const HIGHLIGHT_ENTITY_BORDER_PX: float = 1.0

var _camera: Camera2D
var _workers_root: Node2D
var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _designator: Designator
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _fog: FogOfWar
var _structure_manager: StructureManager
var _static_prop_manager: Node
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
var _order_highlight_target: Node2D = null
var _attack_hover_target: Node2D = null
var _hover_entity: Node2D = null
var _hover_cells: Array[Vector2i] = []
var _order_fail_grid: Vector2i = Pathfinder.UNREACHABLE
var _order_fail_timer: float = 0.0


func _ready() -> void:
	_camera = get_node(camera_path) as Camera2D
	_workers_root = get_node(workers_root_path) as Node2D
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_pathfinder = get_node(pathfinder_path) as Pathfinder
	_designator = get_node(designator_path) as Designator
	_job_board = get_node_or_null(job_board_path) as JobBoard
	_stockpile_manager = get_node_or_null(stockpile_manager_path) as StockpileManager
	_fog = get_node(fog_of_war_path) as FogOfWar
	_structure_manager = get_node_or_null(structure_manager_path) as StructureManager
	_static_prop_manager = get_node_or_null(static_prop_manager_path)
	_neutrals_root = get_node_or_null(neutrals_root_path) as Node2D
	_hostiles_root = get_node_or_null(hostiles_root_path) as Node2D
	EventBus.tile_changed.connect(func(_grid: Vector2i, _new_tile: int) -> void: queue_redraw())


func _process(delta: float) -> void:
	var needs_redraw: bool = false
	if _update_hover_target():
		needs_redraw = true
	if _order_highlight_timer > 0.0:
		_order_highlight_timer = maxf(0.0, _order_highlight_timer - delta)
		if _order_highlight_timer <= 0.0:
			_order_highlight_grid = Pathfinder.UNREACHABLE
			_order_highlight_target = null
		needs_redraw = true
	if _order_fail_timer > 0.0:
		_order_fail_timer = maxf(0.0, _order_fail_timer - delta)
		if _order_fail_timer <= 0.0:
			_order_fail_grid = Pathfinder.UNREACHABLE
		needs_redraw = true
	if _has_selected_path():
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


func selected_worker() -> Worker:
	return _selected[0] if not _selected.is_empty() else null


func selected_workers() -> Array[Worker]:
	return _selected.duplicate()


func select_workers(workers: Array[Worker]) -> void:
	_select_many(workers)


func clear_selection() -> bool:
	if _selected.is_empty():
		return false
	_select_many([])
	return true


func _unhandled_input(event: InputEvent) -> void:
	var primary: int = SettingsManager.primary_mouse_button()
	var secondary: int = SettingsManager.secondary_mouse_button()
	# When a designator mode is active, a plain primary-click anywhere
	# cancels it. The secondary button drives every mode (place, paint,
	# designate), so we never steal those events from the Designator.
	if _designator != null and _designator.current_mode() != Designator.Mode.NONE:
		if event is InputEventMouseButton:
			var mb_d := event as InputEventMouseButton
			if mb_d.pressed and mb_d.button_index == primary:
				_designator.cancel_active()
				var grid: Vector2i = _world_to_grid(_camera.get_global_mouse_position())
				# Collapse the designation palette on any in-map tile click,
				# whether the cell is explored or still under fog of war.
				if _chunk_manager.is_grid_in_map(grid):
					EventBus.default_tile_clicked.emit(grid)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == primary:
			if mb.pressed:
				_begin_drag(mb.position)
			else:
				_finish_drag(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == secondary and not _selected.is_empty():
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
		EventBus.structure_selected.emit(-1, Vector2i.ZERO)
		EventBus.stockpile_selected.emit(null)
		EventBus.build_job_selected.emit(Pathfinder.UNREACHABLE)
	else:
		var workers: Array[Worker] = _worker_under(_drag_end_world)
		if not workers.is_empty():
			_select_many(workers)
			EventBus.structure_selected.emit(-1, Vector2i.ZERO)
			EventBus.stockpile_selected.emit(null)
			EventBus.build_job_selected.emit(Pathfinder.UNREACHABLE)
			EventBus.bot_inspected.emit(null, 0)
		else:
			var npc: Node2D = _npc_under(_drag_end_world)
			if npc != null:
				_select_many([])
				EventBus.structure_selected.emit(-1, Vector2i.ZERO)
				EventBus.stockpile_selected.emit(null)
				EventBus.build_job_selected.emit(Pathfinder.UNREACHABLE)
				var faction_id: int = int(npc.call("faction")) if npc.has_method("faction") else 0
				EventBus.bot_inspected.emit(npc, faction_id)
			elif _try_select_build_job(_drag_end_world):
				_select_many([])
				EventBus.structure_selected.emit(-1, Vector2i.ZERO)
				EventBus.stockpile_selected.emit(null)
				EventBus.bot_inspected.emit(null, 0)
			elif _try_select_stockpile(_drag_end_world):
				_select_many([])
				EventBus.structure_selected.emit(-1, Vector2i.ZERO)
				EventBus.build_job_selected.emit(Pathfinder.UNREACHABLE)
				EventBus.bot_inspected.emit(null, 0)
			elif _try_select_structure(_drag_end_world):
				_select_many([])
				EventBus.stockpile_selected.emit(null)
				EventBus.build_job_selected.emit(Pathfinder.UNREACHABLE)
				EventBus.bot_inspected.emit(null, 0)
			else:
				var grid: Vector2i = _world_to_grid(_drag_end_world)
				_select_many([])
				EventBus.structure_selected.emit(-1, Vector2i.ZERO)
				EventBus.stockpile_selected.emit(null)
				EventBus.build_job_selected.emit(Pathfinder.UNREACHABLE)
				EventBus.bot_inspected.emit(null, 0)
				# Left-click on a teleporter toggles its blocked state so workers
				# won't step on or use it (player-facing kill switch).
				var explored: bool = _fog == null or _fog.is_explored(grid)
				if explored and _chunk_manager.get_tile_at(grid) == TerrainGenerator.TILE_TELEPORTER:
					_chunk_manager.toggle_teleporter_block(grid)
					_show_order_highlight(grid)
				if _chunk_manager.is_grid_in_map(grid):
					EventBus.default_tile_clicked.emit(grid)
	queue_redraw()


func _handle_right_click(shift_held: bool) -> void:
	var world_pos: Vector2 = _camera.get_global_mouse_position()
	# Rescue: if the cursor is on a *downed* colony worker, route to the
	# save flow before any other right-click order so the player can't
	# accidentally try to "attack" their own rebooting bot.
	var downed: Worker = _downed_worker_under(world_pos)
	if downed != null:
		_command_save_downed(downed, shift_held)
		_show_entity_order_highlight(downed)
		return
	# Attack any hostile/neutral under cursor (multi-bot via stand spreading).
	var attack_target: Node2D = _attackable_under(world_pos)
	if attack_target != null:
		_command_group_attack(attack_target, shift_held)
		_show_entity_order_highlight(attack_target)
		return
	var grid: Vector2i = Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)
	if _fog != null and not _fog.is_explored(grid):
		_show_order_failed(grid, "Unexplored")
		return
	var build: BuildJob = _job_board.build_job_at(grid) if _job_board != null else null
	if build != null:
		var worker: Worker = selected_worker()
		if worker != null and is_instance_valid(worker) and _take_or_queue_build_job(worker, build, shift_held):
			_show_order_highlight(build.anchor)
		elif worker != null and is_instance_valid(worker):
			_show_order_failed(grid, "No path", worker)
		return
	if _structure_manager != null \
			and _structure_manager.has_method("has_scrappable_structure") \
			and bool(_structure_manager.call("has_scrappable_structure", grid)) \
			and (_fog == null or _fog.is_cell_visible(grid)):
		var structure_scrapper: Worker = selected_worker()
		if structure_scrapper != null and is_instance_valid(structure_scrapper):
			if shift_held:
				structure_scrapper.queue_command_mine(grid)
			else:
				structure_scrapper.command_mine(grid)
			_show_order_highlight(grid)
		return
	var tile: int = _chunk_manager.get_tile_at(grid)
	if _static_prop_manager != null \
			and _static_prop_manager.has_method("has_mineable_prop") \
			and bool(_static_prop_manager.call("has_mineable_prop", grid)):
		var prop_miner: Worker = selected_worker()
		if prop_miner != null and is_instance_valid(prop_miner):
			if shift_held:
				prop_miner.queue_command_mine(grid)
			else:
				prop_miner.command_mine(grid)
			_show_order_highlight(grid)
		return
	if tile == TerrainGenerator.TILE_WALL \
			or tile == TerrainGenerator.TILE_SERVICE_CORE \
			or tile == TerrainGenerator.TILE_RICH_WALL:
		var miner: Worker = selected_worker()
		if miner != null and is_instance_valid(miner):
			if shift_held:
				miner.queue_command_mine(grid)
			else:
				miner.command_mine(grid)
			_show_order_highlight(grid)
		return
	if tile == TerrainGenerator.TILE_RUST:
		var scraper: Worker = selected_worker()
		if scraper != null and is_instance_valid(scraper):
			if shift_held:
				scraper.queue_command_scrape_rust(grid)
			else:
				scraper.command_scrape_rust(grid)
			_show_order_highlight(grid)
		return
	if _chunk_manager.has_grass(grid):
		var biomass_scraper: Worker = selected_worker()
		if biomass_scraper != null and is_instance_valid(biomass_scraper):
			if shift_held:
				biomass_scraper.queue_command_scrape_biomass(grid)
			else:
				biomass_scraper.command_scrape_biomass(grid)
			_show_order_highlight(grid)
		return
	if tile == TerrainGenerator.TILE_OUTLET:
		if _command_one_worker_to_charge(grid, shift_held):
			_show_order_highlight(grid)
		else:
			_show_order_failed(grid, "Outlet unavailable")
	elif _is_walkable_order_tile(tile):
		if _command_group_move(grid, shift_held):
			_show_order_highlight(grid)
			AudioManager.play_move_here()
		else:
			_show_order_failed(grid, "No path")
	elif _try_command_repair_bench(grid, shift_held):
		pass
	else:
		_show_order_failed(grid, "Blocked tile")


func _try_command_repair_bench(grid: Vector2i, _append: bool) -> bool:
	if _structure_manager == null:
		return false
	var structure: Dictionary = _structure_manager.structure_at(grid)
	if structure.is_empty():
		return false
	var id: int = int(structure.get("id", -1))
	if id != BuildBlueprint.Id.REPAIR_BENCH and id != BuildBlueprint.Id.MAINTENANCE_DOCK:
		return false
	var anchor: Vector2i = structure.get("anchor", grid) as Vector2i
	var sent: bool = false
	for worker in _selected_by_distance(anchor):
		if not worker.has_method("command_repair_at"):
			continue
		var ok: bool = worker.call("command_repair_at", anchor, true)
		if ok:
			sent = true
			break
	if sent:
		_show_order_highlight(grid)
	else:
		_show_order_failed(grid, "Can't reach")
	return true


func _take_or_queue_build_job(worker: Worker, build: BuildJob, append: bool) -> bool:
	if append:
		return worker.queue_command_take_build_job(build)
	return worker.command_take_build_job(build)


func _command_one_worker_to_charge(grid: Vector2i, append: bool = false) -> bool:
	for worker in _selected_by_distance(grid):
		var accepted: bool = worker.queue_command_charge(grid) if append else worker.command_charge(grid)
		if accepted:
			return true
	return false


func _command_group_move(grid: Vector2i, append: bool = false) -> bool:
	var workers: Array[Worker] = _selected_by_distance(grid)
	var assigned: Dictionary = {}
	for worker in workers:
		var target: Vector2i = _best_group_target_for(worker, grid, assigned)
		if target == Pathfinder.UNREACHABLE:
			continue
		var accepted: bool = worker.queue_command_move(target) if append else worker.command_move(target)
		if accepted:
			assigned[target] = true
	return not assigned.is_empty()


func _show_order_highlight(grid: Vector2i) -> void:
	_order_highlight_grid = grid
	_order_highlight_target = null
	_order_highlight_timer = ORDER_HIGHLIGHT_SECONDS
	queue_redraw()


func _show_entity_order_highlight(target: Node2D) -> void:
	_order_highlight_grid = Pathfinder.UNREACHABLE
	_order_highlight_target = target
	_order_highlight_timer = ORDER_HIGHLIGHT_SECONDS
	queue_redraw()


func _show_order_failed(grid: Vector2i, reason: String, worker: Worker = null) -> void:
	_order_fail_grid = grid
	_order_fail_timer = ORDER_FAIL_SECONDS
	var target_worker: Worker = worker if worker != null else selected_worker()
	if target_worker != null and is_instance_valid(target_worker):
		target_worker.show_order_failed(reason)
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
		if candidate != worker.current_grid():
			var route: Dictionary = _pathfinder.find_path_with_teleporters(worker.current_grid(), candidate, _fog)
			var path: PackedVector2Array = route.get("path", PackedVector2Array()) as PackedVector2Array
			if path.is_empty():
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
		or tile == TerrainGenerator.TILE_TELEPORTER \
		or tile == TerrainGenerator.TILE_WATER_SHALLOW \
		or tile == TerrainGenerator.TILE_WATER_PUDDLE


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


func _command_group_attack(target: Node2D, append: bool = false) -> void:
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
		if append:
			worker.queue_command_attack(target, stand)
		else:
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
		if candidate != origin:
			var route: Dictionary = _pathfinder.find_path_with_teleporters(origin, candidate, _fog)
			var path: PackedVector2Array = route.get("path", PackedVector2Array()) as PackedVector2Array
			if path.is_empty():
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


func _update_hover_target() -> bool:
	var old_entity: Node2D = _hover_entity
	var old_cells: Array[Vector2i] = _hover_cells.duplicate()
	_hover_entity = null
	_hover_cells = []
	if _camera == null:
		return old_entity != null or not old_cells.is_empty()
	var vp: Viewport = get_viewport()
	if vp != null and vp.gui_get_hovered_control() != null:
		return old_entity != null or not old_cells.is_empty()
	var world_pos: Vector2 = _camera.get_global_mouse_position()
	var workers: Array[Worker] = _worker_under(world_pos)
	if not workers.is_empty():
		_hover_entity = workers[0]
		return _hover_changed(old_entity, old_cells)
	var npc: Node2D = _npc_under(world_pos)
	if npc != null:
		_hover_entity = npc
		return _hover_changed(old_entity, old_cells)
	var grid := Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)
	if _fog != null and not _fog.is_explored(grid):
		return _hover_changed(old_entity, old_cells)
	var structure: Dictionary = _structure_under(grid)
	if not structure.is_empty():
		if bool(structure.get("generated", false)) and _fog != null and not _fog.is_cell_visible(grid):
			return _hover_changed(old_entity, old_cells)
		var raw_cells: Array = structure.get("cells", []) as Array
		for cell in raw_cells:
			_hover_cells.append(cell as Vector2i)
		return _hover_changed(old_entity, old_cells)
	if _static_prop_manager != null \
			and _static_prop_manager.has_method("has_mineable_prop") \
			and bool(_static_prop_manager.call("has_mineable_prop", grid)):
		_hover_cells = [grid]
	return _hover_changed(old_entity, old_cells)


func _hover_changed(old_entity: Node2D, old_cells: Array[Vector2i]) -> bool:
	if old_entity != _hover_entity:
		return true
	if old_cells.size() != _hover_cells.size():
		return true
	for i in old_cells.size():
		if old_cells[i] != _hover_cells[i]:
			return true
	return false


func _structure_under(grid: Vector2i) -> Dictionary:
	if _structure_manager == null:
		return {}
	return _structure_manager.structure_at(grid)


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


func _downed_worker_under(world_pos: Vector2) -> Worker:
	var best: Worker = null
	var best_d: float = SELECT_RADIUS_PX
	for child in _workers_root.get_children():
		var w := child as Worker
		if w == null or not w.has_method("is_downed") or not w.is_downed():
			continue
		var d: float = (w.position - world_pos).length()
		if d <= best_d:
			best = w
			best_d = d
	return best


func _command_save_downed(target: Worker, append: bool) -> void:
	# First selected worker who can path to the downed body wins the save.
	for worker in _selected_by_distance(target.current_grid()):
		if worker == target:
			continue
		var ok: bool = false
		if append:
			ok = worker.queue_command_save(target)
		else:
			ok = worker.command_save(target)
		if ok:
			return
	# Nothing took the order — surface the failure visually on the body.
	_show_order_failed(target.current_grid(), "Can't save")


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
	var grid: Vector2i = _world_to_grid(world_pos)
	if _fog != null and not _fog.is_explored(grid):
		return false
	var structure: Dictionary = _structure_manager.structure_at(grid)
	if structure.is_empty():
		return false
	if bool(structure.get("generated", false)) and _fog != null and not _fog.is_cell_visible(grid):
		return false
	EventBus.structure_selected.emit(int(structure["id"]), structure["anchor"] as Vector2i)
	return true


func _try_select_stockpile(world_pos: Vector2) -> bool:
	if _stockpile_manager == null:
		return false
	var grid := Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)
	if _fog != null and not _fog.is_explored(grid):
		return false
	var zone: StockpileZone = _stockpile_manager.zone_at(grid)
	if zone == null:
		return false
	EventBus.stockpile_selected.emit(zone)
	return true


func _try_select_build_job(world_pos: Vector2) -> bool:
	if _job_board == null:
		return false
	var grid := Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)
	if _fog != null and not _fog.is_explored(grid):
		return false
	var build: BuildJob = _job_board.build_job_at(grid)
	if build == null:
		return false
	EventBus.build_job_selected.emit(build.anchor)
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


func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / Chunk.TILE_PIXELS)),
		int(floor(world_pos.y / Chunk.TILE_PIXELS)),
	)


func _has_selected_path() -> bool:
	for worker in _selected:
		if worker == null or not is_instance_valid(worker):
			continue
		if not worker.active_path_points().is_empty():
			return true
	return false


func _draw() -> void:
	_draw_selected_paths()
	_draw_blocked_teleporters()
	var designator_idle: bool = _designator == null or _designator.current_mode() == Designator.Mode.NONE
	if designator_idle and _hover_entity != null and is_instance_valid(_hover_entity) and _hover_entity != _attack_hover_target:
		_draw_entity_highlight(_hover_entity, HOVER_FILL, HOVER_BORDER, 1.0)
	if designator_idle and not _hover_cells.is_empty():
		for cell in _hover_cells:
			var hover_origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
			draw_rect(Rect2(hover_origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)), HOVER_FILL)
			draw_rect(Rect2(hover_origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS)), HOVER_BORDER, false, 1.5)
	if designator_idle and _attack_hover_target != null and is_instance_valid(_attack_hover_target):
		_draw_entity_highlight(_attack_hover_target, ATTACK_HOVER_FILL, ATTACK_HOVER_BORDER, 1.0)
	if _order_fail_grid != Pathfinder.UNREACHABLE:
		var fail_alpha: float = clampf(_order_fail_timer / ORDER_FAIL_SECONDS, 0.0, 1.0)
		var fail_origin := Vector2(_order_fail_grid.x * Chunk.TILE_PIXELS, _order_fail_grid.y * Chunk.TILE_PIXELS)
		var fail_rect := Rect2(fail_origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(fail_rect, Color(ORDER_FAIL_FILL.r, ORDER_FAIL_FILL.g, ORDER_FAIL_FILL.b, ORDER_FAIL_FILL.a * fail_alpha))
		draw_rect(fail_rect, Color(ORDER_FAIL_BORDER.r, ORDER_FAIL_BORDER.g, ORDER_FAIL_BORDER.b, ORDER_FAIL_BORDER.a * fail_alpha), false, HIGHLIGHT_BORDER_PX)
	if _order_highlight_target != null and is_instance_valid(_order_highlight_target):
		var alpha_target: float = clampf(_order_highlight_timer / ORDER_HIGHLIGHT_SECONDS, 0.0, 1.0)
		_draw_entity_highlight(_order_highlight_target, ORDER_HIGHLIGHT_FILL, ORDER_HIGHLIGHT_BORDER, alpha_target)
	if _order_highlight_grid != Pathfinder.UNREACHABLE:
		var alpha: float = clampf(_order_highlight_timer / ORDER_HIGHLIGHT_SECONDS, 0.0, 1.0)
		var origin := Vector2(_order_highlight_grid.x * Chunk.TILE_PIXELS, _order_highlight_grid.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, Color(ORDER_HIGHLIGHT_FILL.r, ORDER_HIGHLIGHT_FILL.g, ORDER_HIGHLIGHT_FILL.b, ORDER_HIGHLIGHT_FILL.a * alpha))
		draw_rect(rect, Color(ORDER_HIGHLIGHT_BORDER.r, ORDER_HIGHLIGHT_BORDER.g, ORDER_HIGHLIGHT_BORDER.b, ORDER_HIGHLIGHT_BORDER.a * alpha), false, HIGHLIGHT_BORDER_PX)
	if _dragging:
		var is_box: bool = (_drag_end_screen - _drag_start_screen).length() >= DRAG_THRESHOLD_PX
		if not is_box:
			return
		var drag_origin := Vector2(minf(_drag_start_world.x, _drag_end_world.x), minf(_drag_start_world.y, _drag_end_world.y))
		var size := Vector2(absf(_drag_start_world.x - _drag_end_world.x), absf(_drag_start_world.y - _drag_end_world.y))
		var drag_rect := Rect2(drag_origin, size)
		draw_rect(drag_rect, DRAG_FILL)
		draw_rect(drag_rect, DRAG_BORDER, false, DRAG_BORDER_PX)


func _draw_blocked_teleporters() -> void:
	if _chunk_manager == null:
		return
	for cell in _chunk_manager.teleporter_cells_all():
		if not _chunk_manager.is_teleporter_blocked(cell):
			continue
		if _fog != null and not _fog.is_explored(cell):
			continue
		var origin := Vector2(cell.x * Chunk.TILE_PIXELS, cell.y * Chunk.TILE_PIXELS)
		var rect := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(rect, Color(0.9, 0.2, 0.2, 0.18))
		var p0: Vector2 = origin + Vector2(4, 4)
		var p1: Vector2 = origin + Vector2(Chunk.TILE_PIXELS - 4, Chunk.TILE_PIXELS - 4)
		var p2: Vector2 = origin + Vector2(Chunk.TILE_PIXELS - 4, 4)
		var p3: Vector2 = origin + Vector2(4, Chunk.TILE_PIXELS - 4)
		var color := Color(1.0, 0.32, 0.28, 0.9)
		draw_line(p0, p1, color, 2.0, true)
		draw_line(p2, p3, color, 2.0, true)


func _draw_selected_paths() -> void:
	for worker in _selected:
		if worker == null or not is_instance_valid(worker):
			continue
		var pts: PackedVector2Array = worker.active_path_points()
		if pts.size() < 2:
			continue
		draw_polyline(pts, PATH_PREVIEW_COLOR, 1.0, true)


func _draw_entity_highlight(target: Node2D, fill: Color, border: Color, alpha: float) -> void:
	var center: Vector2 = target.position
	var radius: float = SELECT_RADIUS_PX + 3.0
	draw_circle(center, radius, Color(fill.r, fill.g, fill.b, fill.a * alpha))
	draw_arc(center, radius, 0.0, TAU, 32, Color(border.r, border.g, border.b, border.a * alpha), HIGHLIGHT_ENTITY_BORDER_PX)
