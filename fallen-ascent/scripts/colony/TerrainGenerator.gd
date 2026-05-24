class_name TerrainGenerator
extends RefCounted
##
## Per-chunk terrain selection. Pure — same (site_seed, chunk_coord) always
## yields the same tile layout.
##
## Layout style: BLAME!-inspired megastructure — a maze of rectangular rooms
## connected by tight corridors, with occasional shortcut loops and void
## pockets in dense wall sections. Cross-chunk continuity is achieved by
## deriving edge doorways from a hash of the shared (canonicalized) chunk
## pair, so both sides of a boundary independently agree on doorway
## positions without any global state.
##
## Tile ids: 0=floor, 1=wall, 2=debris, 3=void.

const TILE_FLOOR: int = 0
const TILE_WALL: int = 1
const TILE_DEBRIS: int = 2
const TILE_VOID: int = 3

const _DOOR_PROBABILITY: float = 0.7
const _SHORTCUT_PROBABILITY: float = 0.2
const _DEBRIS_NOISE_THRESHOLD: float = 0.45
const _VOID_PROBABILITY: float = 0.3
const _VOID_NEIGHBOUR_THRESHOLD: int = 6
const _ROOM_MIN: int = 4
const _ROOM_MAX: int = 12
const _ROOM_TARGET_MIN: int = 1
const _ROOM_TARGET_MAX: int = 4
const _ROOM_PLACEMENT_ATTEMPTS: int = 20
const _EDGE_MARGIN: int = 2


static func make_noise(site_seed: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = site_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.05
	return n


## Fills `out` (size = chunk_size * chunk_size) with tile ids for one chunk.
## `out` is passed in to avoid per-chunk allocation churn.
static func populate(
	noise: FastNoiseLite,
	chunk_coord: Vector2i,
	chunk_size: int,
	out: PackedInt32Array,
) -> void:
	var site_seed: int = noise.seed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site_seed, chunk_coord.x, chunk_coord.y, "chunk"])

	# 1. Solid mass.
	for i in chunk_size * chunk_size:
		out[i] = TILE_WALL

	# 2. Edge doorways, agreed-upon with each neighbour.
	var doors: Array[Vector2i] = _edge_doors(site_seed, chunk_coord, chunk_size)

	# 3. Carve rooms.
	var rooms: Array[Rect2i] = _place_rooms(rng, chunk_size)
	for room in rooms:
		_fill_rect(out, chunk_size, room, TILE_FLOOR)

	# 4. Corridors: doorway -> nearest room, plus room-to-room spine.
	for door in doors:
		out[door.y * chunk_size + door.x] = TILE_FLOOR
		var target: Vector2i = _nearest_room_center(door, rooms)
		if target.x < 0:
			target = Vector2i(chunk_size / 2, chunk_size / 2)
		_carve_l(out, chunk_size, door, target, rng)
	for i in range(1, rooms.size()):
		_carve_l(out, chunk_size, _rect_center(rooms[i - 1]), _rect_center(rooms[i]), rng)

	# 5. Shortcut loop (BLAME! signature).
	if rooms.size() >= 3 and rng.randf() < _SHORTCUT_PROBABILITY:
		var a_idx: int = rng.randi_range(0, rooms.size() - 1)
		var b_idx: int = rng.randi_range(0, rooms.size() - 1)
		if a_idx != b_idx:
			_carve_l(out, chunk_size, _rect_center(rooms[a_idx]), _rect_center(rooms[b_idx]), rng)

	# 6. Debris speckle on floor (still walkable).
	var base_x: int = chunk_coord.x * chunk_size
	var base_y: int = chunk_coord.y * chunk_size
	for ly in chunk_size:
		for lx in chunk_size:
			var idx: int = ly * chunk_size + lx
			if out[idx] != TILE_FLOOR:
				continue
			if noise.get_noise_2d(base_x + lx, base_y + ly) > _DEBRIS_NOISE_THRESHOLD:
				out[idx] = TILE_DEBRIS

	# 7. Void pockets inside deep wall mass.
	_void_pass(out, chunk_size, rng)


static func tile_color(t: int) -> Color:
	match t:
		TILE_FLOOR:  return Color(0.22, 0.24, 0.28)
		TILE_WALL:   return Color(0.55, 0.55, 0.58)
		TILE_DEBRIS: return Color(0.35, 0.30, 0.25)
		TILE_VOID:   return Color(0.06, 0.06, 0.09)
	return Color.MAGENTA


static func _edge_doors(site_seed: int, chunk_coord: Vector2i, chunk_size: int) -> Array[Vector2i]:
	var doors: Array[Vector2i] = []
	var north: int = _edge_door_offset(site_seed, chunk_coord, Vector2i(chunk_coord.x, chunk_coord.y - 1), chunk_size)
	if north >= 0:
		doors.append(Vector2i(north, 0))
	var south: int = _edge_door_offset(site_seed, chunk_coord, Vector2i(chunk_coord.x, chunk_coord.y + 1), chunk_size)
	if south >= 0:
		doors.append(Vector2i(south, chunk_size - 1))
	var west: int = _edge_door_offset(site_seed, chunk_coord, Vector2i(chunk_coord.x - 1, chunk_coord.y), chunk_size)
	if west >= 0:
		doors.append(Vector2i(0, west))
	var east: int = _edge_door_offset(site_seed, chunk_coord, Vector2i(chunk_coord.x + 1, chunk_coord.y), chunk_size)
	if east >= 0:
		doors.append(Vector2i(chunk_size - 1, east))
	return doors


## Returns the door's offset along the shared edge, or -1 if the edge is sealed.
## Hash key is canonicalised over the two neighbouring chunk coords so both
## sides agree on the result.
static func _edge_door_offset(site_seed: int, a: Vector2i, b: Vector2i, chunk_size: int) -> int:
	var lo: Vector2i = a
	var hi: Vector2i = b
	if (b.x < a.x) or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site_seed, lo.x, lo.y, hi.x, hi.y, "door"])
	if rng.randf() > _DOOR_PROBABILITY:
		return -1
	return rng.randi_range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN - 1)


static func _place_rooms(rng: RandomNumberGenerator, chunk_size: int) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	var target: int = rng.randi_range(_ROOM_TARGET_MIN, _ROOM_TARGET_MAX)
	for _attempt in _ROOM_PLACEMENT_ATTEMPTS:
		if rooms.size() >= target:
			break
		var w: int = rng.randi_range(_ROOM_MIN, _ROOM_MAX)
		var h: int = rng.randi_range(_ROOM_MIN, _ROOM_MAX)
		var max_x: int = chunk_size - _EDGE_MARGIN - w
		var max_y: int = chunk_size - _EDGE_MARGIN - h
		if max_x <= _EDGE_MARGIN or max_y <= _EDGE_MARGIN:
			continue
		var x: int = rng.randi_range(_EDGE_MARGIN, max_x)
		var y: int = rng.randi_range(_EDGE_MARGIN, max_y)
		var candidate := Rect2i(x, y, w, h)
		var clash: bool = false
		for existing in rooms:
			var expanded := Rect2i(existing.position - Vector2i.ONE, existing.size + Vector2i(2, 2))
			if expanded.intersects(candidate):
				clash = true
				break
		if not clash:
			rooms.append(candidate)
	return rooms


static func _fill_rect(out: PackedInt32Array, chunk_size: int, rect: Rect2i, tile: int) -> void:
	for ly in range(rect.position.y, rect.position.y + rect.size.y):
		for lx in range(rect.position.x, rect.position.x + rect.size.x):
			out[ly * chunk_size + lx] = tile


static func _carve_l(
	out: PackedInt32Array,
	chunk_size: int,
	from: Vector2i,
	to: Vector2i,
	rng: RandomNumberGenerator,
) -> void:
	if rng.randi() % 2 == 0:
		_carve_h(out, chunk_size, from.x, to.x, from.y)
		_carve_v(out, chunk_size, from.y, to.y, to.x)
	else:
		_carve_v(out, chunk_size, from.y, to.y, from.x)
		_carve_h(out, chunk_size, from.x, to.x, to.y)


static func _carve_h(out: PackedInt32Array, chunk_size: int, x0: int, x1: int, y: int) -> void:
	if y < 0 or y >= chunk_size:
		return
	var lo: int = mini(x0, x1)
	var hi: int = maxi(x0, x1)
	lo = clampi(lo, 0, chunk_size - 1)
	hi = clampi(hi, 0, chunk_size - 1)
	for x in range(lo, hi + 1):
		out[y * chunk_size + x] = TILE_FLOOR


static func _carve_v(out: PackedInt32Array, chunk_size: int, y0: int, y1: int, x: int) -> void:
	if x < 0 or x >= chunk_size:
		return
	var lo: int = mini(y0, y1)
	var hi: int = maxi(y0, y1)
	lo = clampi(lo, 0, chunk_size - 1)
	hi = clampi(hi, 0, chunk_size - 1)
	for y in range(lo, hi + 1):
		out[y * chunk_size + x] = TILE_FLOOR


static func _rect_center(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


## Chebyshev-nearest room center. Returns Vector2i(-1, -1) if no rooms exist.
static func _nearest_room_center(from: Vector2i, rooms: Array[Rect2i]) -> Vector2i:
	if rooms.is_empty():
		return Vector2i(-1, -1)
	var best := _rect_center(rooms[0])
	var best_d: int = maxi(absi(from.x - best.x), absi(from.y - best.y))
	for i in range(1, rooms.size()):
		var c := _rect_center(rooms[i])
		var d: int = maxi(absi(from.x - c.x), absi(from.y - c.y))
		if d < best_d:
			best = c
			best_d = d
	return best


## Converts deep-interior wall tiles into void. Reads from a snapshot so the
## sweep is order-independent.
static func _void_pass(out: PackedInt32Array, chunk_size: int, rng: RandomNumberGenerator) -> void:
	var snapshot: PackedInt32Array = out.duplicate()
	for ly in chunk_size:
		for lx in chunk_size:
			var idx: int = ly * chunk_size + lx
			if snapshot[idx] != TILE_WALL:
				continue
			var wall_count: int = 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = lx + dx
					var ny: int = ly + dy
					if nx < 0 or nx >= chunk_size or ny < 0 or ny >= chunk_size:
						wall_count += 1
						continue
					if snapshot[ny * chunk_size + nx] == TILE_WALL:
						wall_count += 1
			if wall_count >= _VOID_NEIGHBOUR_THRESHOLD and rng.randf() < _VOID_PROBABILITY:
				out[idx] = TILE_VOID
