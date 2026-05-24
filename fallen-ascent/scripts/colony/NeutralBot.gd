class_name NeutralBot
extends Node2D
##
## Ambient neutral bot. No jobs, selection, or colony systems. Picks reachable
## walk targets and wanders forever.
##

const ENTITY_ATLAS: Texture2D = preload("res://resources/entities/placeholder_entities_atlas.png")
const NEUTRAL_REGION := Rect2(Vector2(16, 0), Vector2(16, 16))
const MOVE_SPEED_PX_PER_SEC: float = 34.0
const ARRIVE_EPSILON_PX: float = 1.0
const WANDER_RADIUS: int = 28
const PICK_ATTEMPTS: int = 36

var _chunk_manager: ChunkManager
var _pathfinder: Pathfinder
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _wander_timer: Timer


func setup(chunk_manager: ChunkManager, pathfinder: Pathfinder) -> void:
	_chunk_manager = chunk_manager
	_pathfinder = pathfinder


func _ready() -> void:
	_wander_timer = Timer.new()
	_wander_timer.one_shot = true
	_wander_timer.timeout.connect(_on_wander_timer_timeout)
	add_child(_wander_timer)
	set_process(false)
	_schedule_wander(0.2, 2.0)


func current_grid() -> Vector2i:
	return Vector2i(
		int(floor(position.x / Chunk.TILE_PIXELS)),
		int(floor(position.y / Chunk.TILE_PIXELS)),
	)


func _process(delta: float) -> void:
	if _advance_path(delta):
		_path = PackedVector2Array()
		set_process(false)
		_schedule_wander(1.0, 4.0)


func _advance_path(delta: float) -> bool:
	if _path.is_empty() or _path_index >= _path.size():
		return true
	var step: float = MOVE_SPEED_PX_PER_SEC * delta
	while step > 0.0 and _path_index < _path.size():
		var target: Vector2 = _path[_path_index]
		var to_target: Vector2 = target - position
		var dist: float = to_target.length()
		if dist <= step + ARRIVE_EPSILON_PX:
			position = target
			step -= dist
			_path_index += 1
		else:
			position += to_target / dist * step
			step = 0.0
	return _path_index >= _path.size()


func _pick_next_wander() -> void:
	if _chunk_manager == null or _pathfinder == null:
		_schedule_wander(1.0, 4.0)
		return
	var origin: Vector2i = current_grid()
	for _i in range(PICK_ATTEMPTS):
		var candidate := origin + Vector2i(
			randi_range(-WANDER_RADIUS, WANDER_RADIUS),
			randi_range(-WANDER_RADIUS, WANDER_RADIUS),
		)
		if not _chunk_manager.is_walkable(candidate):
			continue
		var candidate_path: PackedVector2Array = _pathfinder.find_path(origin, candidate)
		if candidate_path.is_empty():
			continue
		_path = candidate_path
		_path_index = 0
		set_process(true)
		return
	_schedule_wander(1.0, 4.0)


func _schedule_wander(min_seconds: float, max_seconds: float) -> void:
	_wander_timer.start(randf_range(min_seconds, max_seconds))


func _on_wander_timer_timeout() -> void:
	_pick_next_wander()


func _draw() -> void:
	draw_texture_rect_region(ENTITY_ATLAS, Rect2(Vector2(-8, -8), Vector2(16, 16)), NEUTRAL_REGION)
