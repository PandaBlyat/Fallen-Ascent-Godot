class_name StockpileManager
extends Node2D
##
## Owns the set of StockpileZones for the colony. The zones live as children
## of this node so they share its draw order (above chunks, below workers).
## When a zone is created or a new item is dropped, this manager pairs free
## cells with unreserved items and posts HaulJobs.
##

signal zone_added(zone: StockpileZone)
signal stockpile_changed()

@export var job_board_path: NodePath
@export var chunk_manager_path: NodePath
@export var items_root_path: NodePath

var _job_board: JobBoard
var _chunk_manager: ChunkManager
var _items_root: Node2D
var zones: Array[StockpileZone] = []


func _ready() -> void:
	_job_board = get_node(job_board_path) as JobBoard
	_chunk_manager = get_node(chunk_manager_path) as ChunkManager
	_items_root = get_node(items_root_path) as Node2D


func create_zone(rect_cells: Array[Vector2i]) -> void:
	var walkable: Array[Vector2i] = []
	for c in rect_cells:
		if _chunk_manager.is_walkable(c):
			walkable.append(c)
	if walkable.is_empty():
		return
	var zone := StockpileZone.new()
	add_child(zone)
	zone.setup(walkable)
	zones.append(zone)
	zone_added.emit(zone)
	stockpile_changed.emit()
	_match_loose_items()


## Iterate loose items and post a HaulJob for each that has an open slot.
func _match_loose_items() -> void:
	if _items_root == null:
		return
	for child in _items_root.get_children():
		var item := child as Item
		if item == null or item.reserved_by != null:
			continue
		_try_post_haul_for(item)


func on_item_spawned(item: Item) -> void:
	_try_post_haul_for(item)


func _try_post_haul_for(item: Item) -> void:
	for zone in zones:
		var cell_v: Variant = zone.first_free_cell()
		if cell_v == null:
			continue
		var cell: Vector2i = cell_v
		zone.reserve(cell)
		item.reserved_by = self
		_job_board.add_haul_job(item, zone, cell)
		return


func total_stored() -> int:
	var n: int = 0
	for z in zones:
		n += z.stored_count()
	return n
