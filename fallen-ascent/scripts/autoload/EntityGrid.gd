extends Node
##
## Coarse spatial hash for entity perception queries. Bots register on
## _ready, refresh their bucket on each perception tick (cheap dict op),
## and query nearby buckets instead of iterating the full faction roster.
##
## Buckets are BUCKET_SIZE tiles on a side. A perception radius `r` touches
## at most ((r/BUCKET_SIZE)*2 + 2)^2 buckets, so we scan ~2x2 buckets at
## radius 7 with BUCKET_SIZE=8.
##

const BUCKET_SIZE: int = 8

const FACTION_COLONY: int = 0
const FACTION_NEUTRAL: int = 1
const FACTION_HOSTILE: int = 2

var _buckets_by_faction: Dictionary = {}   ## faction -> Dictionary[Vector2i, Array[Node]]
var _last_bucket: Dictionary = {}          ## instance_id -> Vector2i
var _node_faction: Dictionary = {}         ## instance_id -> int


func _ready() -> void:
	_buckets_by_faction[FACTION_COLONY] = {}
	_buckets_by_faction[FACTION_NEUTRAL] = {}
	_buckets_by_faction[FACTION_HOSTILE] = {}


## Bucket coord for a tile grid coord. Arithmetic shift right gives floor
## division for both positive and negative ints (BUCKET_SIZE must be 8).
static func bucket_of(grid: Vector2i) -> Vector2i:
	return Vector2i(grid.x >> 3, grid.y >> 3)


func register(node: Node, faction: int, grid: Vector2i) -> void:
	var id: int = node.get_instance_id()
	if _node_faction.has(id):
		return
	var bucket: Vector2i = bucket_of(grid)
	_node_faction[id] = faction
	_last_bucket[id] = bucket
	_add_to_bucket(faction, bucket, node)


func unregister(node: Node) -> void:
	var id: int = node.get_instance_id()
	if not _node_faction.has(id):
		return
	var faction: int = int(_node_faction[id])
	var bucket: Vector2i = _last_bucket[id] as Vector2i
	_remove_from_bucket(faction, bucket, node)
	_node_faction.erase(id)
	_last_bucket.erase(id)


## Move `node` to the bucket for `grid`. No-op if the bucket did not change.
func update_position(node: Node, grid: Vector2i) -> void:
	var id: int = node.get_instance_id()
	if not _node_faction.has(id):
		return
	var new_bucket: Vector2i = bucket_of(grid)
	var old_bucket: Vector2i = _last_bucket[id] as Vector2i
	if new_bucket == old_bucket:
		return
	var faction: int = int(_node_faction[id])
	_remove_from_bucket(faction, old_bucket, node)
	_add_to_bucket(faction, new_bucket, node)
	_last_bucket[id] = new_bucket


## All registered nodes of `faction` whose bucket lies within `radius_tiles`
## of `origin`. Returned set is a superset of the true neighborhood (a few
## stale entries from cells outside the radius are possible); callers must
## still filter by exact distance.
func query(faction: int, origin: Vector2i, radius_tiles: int) -> Array:
	var out: Array = []
	query_into(faction, origin, radius_tiles, out)
	return out


func query_into(faction: int, origin: Vector2i, radius_tiles: int, out: Array) -> void:
	out.clear()
	var buckets: Dictionary = _buckets_by_faction.get(faction, {}) as Dictionary
	if buckets.is_empty():
		return
	var origin_bucket: Vector2i = bucket_of(origin)
	var span: int = int(ceil(float(radius_tiles) / float(BUCKET_SIZE)))
	for by in range(origin_bucket.y - span, origin_bucket.y + span + 1):
		for bx in range(origin_bucket.x - span, origin_bucket.x + span + 1):
			var key := Vector2i(bx, by)
			if not buckets.has(key):
				continue
			for n in buckets[key] as Array:
				out.append(n)


func _add_to_bucket(faction: int, bucket: Vector2i, node: Node) -> void:
	var buckets: Dictionary = _buckets_by_faction[faction] as Dictionary
	if not buckets.has(bucket):
		buckets[bucket] = []
	(buckets[bucket] as Array).append(node)


func _remove_from_bucket(faction: int, bucket: Vector2i, node: Node) -> void:
	var buckets: Dictionary = _buckets_by_faction[faction] as Dictionary
	if not buckets.has(bucket):
		return
	var bucket_arr: Array = buckets[bucket] as Array
	bucket_arr.erase(node)
	if bucket_arr.is_empty():
		buckets.erase(bucket)
