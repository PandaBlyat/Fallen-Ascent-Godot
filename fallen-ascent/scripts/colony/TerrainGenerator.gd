class_name TerrainGenerator
extends RefCounted
##
## Per-chunk terrain selection. Pure: same (site_seed, chunk_coord) always
## yields same tile layout.
##
## Layout style: BLAME!-inspired megastructure with irregular chambers,
## continuous cross-boundary utility conduits, catwalks bridging deep voids,
## load-bearing pillars, and heavy industrial machinery cores.
##
## Tile ids: 0=floor, 1=wall, 2=debris, 3=void, 4=outlet, 5=service core,
## 6=conduit floor, 7=rust sludge, 8=rich wall, 9=teleporter.

const TILE_FLOOR: int = 0
const TILE_WALL: int = 1
const TILE_DEBRIS: int = 2
const TILE_VOID: int = 3
const TILE_OUTLET: int = 4
const TILE_SERVICE_CORE: int = 5
const TILE_CONDUIT: int = 6
const TILE_RUST: int = 7
const TILE_RICH_WALL: int = 8
const TILE_TELEPORTER: int = 9

# Global fallbacks & boundary-critical constants
const _DOOR_PROBABILITY: float = 0.74
const _SHORTCUT_PROBABILITY: float = 0.34
const _DEAD_END_PROBABILITY: float = 0.55      ## per-chunk chance to attempt one dead-end stub
const _DEAD_END_COUNT_MIN: int = 1
const _DEAD_END_COUNT_MAX: int = 3
const _DEAD_END_MIN_LENGTH: int = 3
const _DEAD_END_MAX_LENGTH: int = 7
const _DEBRIS_NOISE_THRESHOLD: float = 0.45
const _CONDUIT_NOISE_THRESHOLD: float = 0.56
const _RUST_NOISE_THRESHOLD: float = -0.62
const _SERVICE_CORE_NOISE_THRESHOLD: float = 0.67
const _RICH_WALL_NOISE_THRESHOLD: float = 0.61
const _TELEPORTER_NOISE_THRESHOLD: float = 0.78
const _VOID_NEIGHBOUR_THRESHOLD: int = 6
const _ROOM_MIN: int = 4
const _ROOM_MAX: int = 14
const _ROOM_TARGET_MIN: int = 2
const _ROOM_TARGET_MAX: int = 5
const _ROOM_PLACEMENT_ATTEMPTS: int = 36
const _EDGE_MARGIN: int = 2
const _VOID_CLUSTER_MIN: int = 2
const _VOID_CLUSTER_MAX: int = 5
const _VOID_CLUSTER_RADIUS_MIN: int = 2
const _VOID_CLUSTER_RADIUS_MAX: int = 6


static func make_noise(site_seed: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = site_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.05
	return n


## Evaluates the macro-scale structural zone for a chunk using low-frequency sampling.
static func get_zone(noise: FastNoiseLite, chunk_coord: Vector2i) -> int:
	# Multiplying by a small factor keeps the zone continuous across multiple adjacent chunks.
	var zone_val: float = noise.get_noise_2d(chunk_coord.x * 4.0, chunk_coord.y * 4.0)
	if zone_val < -0.5:
		return 0 # The Abyss
	elif zone_val < -0.15:
		return 1 # The Industrial Core
	elif zone_val < 0.2:
		return 2 # Habitation Blocks
	elif zone_val < 0.55:
		return 3 # Lithic Vault
	else:
		return 4 # Structural Grid


## Fills `out` (size = chunk_size * chunk_size) with tile ids for one chunk.
static func populate(
	noise: FastNoiseLite,
	chunk_coord: Vector2i,
	chunk_size: int,
	out: PackedInt32Array,
) -> void:
	var site_seed: int = noise.seed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site_seed, chunk_coord.x, chunk_coord.y, "chunk"])

	# Retrieve the structural zone for parameter assignment
	var zone: int = get_zone(noise, chunk_coord)

	# 1. Zone configuration overrides
	var shortcut_prob: float = _SHORTCUT_PROBABILITY
	var room_min_size: int = _ROOM_MIN
	var room_max_size: int = _ROOM_MAX
	var room_target_min: int = _ROOM_TARGET_MIN
	var room_target_max: int = _ROOM_TARGET_MAX
	var room_attempts: int = _ROOM_PLACEMENT_ATTEMPTS

	var void_min: int = _VOID_CLUSTER_MIN
	var void_max: int = _VOID_CLUSTER_MAX
	var void_rad_min: int = _VOID_CLUSTER_RADIUS_MIN
	var void_rad_max: int = _VOID_CLUSTER_RADIUS_MAX

	var conduit_threshold: float = _CONDUIT_NOISE_THRESHOLD
	var rust_threshold: float = _RUST_NOISE_THRESHOLD
	var debris_threshold: float = _DEBRIS_NOISE_THRESHOLD
	var service_threshold: float = _SERVICE_CORE_NOISE_THRESHOLD
	var rich_threshold: float = _RICH_WALL_NOISE_THRESHOLD

	var max_corridor_width: int = 3

	match zone:
		0: # The Abyss (Void-heavy / Catwalk network)
			room_target_min = 1
			room_target_max = 2
			room_min_size = 3
			room_max_size = 6
			void_min = 6
			void_max = 10
			void_rad_min = 4
			void_rad_max = 8
			shortcut_prob = 0.65
			conduit_threshold = 0.45 # More safety steel catwalks
			rust_threshold = -0.50

		1: # The Industrial Core (Dense machinery / Conduits)
			room_target_min = 3
			room_target_max = 5
			room_min_size = 6
			room_max_size = 12
			void_min = 0
			void_max = 1
			service_threshold = 0.48 # Greatly increased service cores
			conduit_threshold = 0.40 # Heavy floor lines

		2: # Habitation Blocks (Compartmentalized chambers)
			room_target_min = 4
			room_target_max = 7
			room_min_size = 4
			room_max_size = 8
			void_min = 0
			void_max = 0 # No hazard voids in residential blocks
			shortcut_prob = 0.15

		3: # Lithic Vault (Dense stone / Resource veins)
			room_target_min = 1
			room_target_max = 3
			room_min_size = 3
			room_max_size = 5
			void_min = 1
			void_max = 3
			rich_threshold = 0.35 # Heavy concentrations of rich walls
			max_corridor_width = 1 # Cramped, narrow shafts

		4: # Structural Grid (Vast halls / Support pillars)
			room_target_min = 2
			room_target_max = 3
			room_min_size = 8
			room_max_size = 14
			void_min = 2
			void_max = 4
			void_rad_min = 3
			void_rad_max = 5
			max_corridor_width = 3 # Wider thoroughfares

	# 2. Solid mass.
	for i in chunk_size * chunk_size:
		out[i] = TILE_WALL

	# 3. Edge doorways.
	# Note: door placement relies on raw constants to guarantee alignment on chunk edges.
	var doors: Array[Vector2i] = _edge_doors(site_seed, chunk_coord, chunk_size)

	# 4. Carve rooms.
	var rooms: Array[Rect2i] = _place_rooms(
		rng, chunk_size, room_target_min, room_target_max, room_min_size, room_max_size, room_attempts
	)
	for room in rooms:
		_carve_room(out, chunk_size, room, rng, zone)

	# 5. Generate voids inside walls early.
	_void_pass(out, chunk_size, rng, void_min, void_max, void_rad_min, void_rad_max)

	# 6. Corridors: doorway -> nearest room, plus room-to-room spine.
	for door in doors:
		out[door.y * chunk_size + door.x] = TILE_FLOOR
		var target: Vector2i = _nearest_room_center(door, rooms)
		if target.x < 0:
			target = Vector2i(chunk_size / 2, chunk_size / 2)
		_carve_corridor(out, chunk_size, door, target, rng, max_corridor_width)
	for i in range(1, rooms.size()):
		_carve_corridor(out, chunk_size, _rect_center(rooms[i - 1]), _rect_center(rooms[i]), rng, max_corridor_width)

	# 7. Shortcut loop (corridors intersecting voids create catwalk networks).
	if rooms.size() >= 3 and rng.randf() < shortcut_prob:
		var a_idx: int = rng.randi_range(0, rooms.size() - 1)
		var b_idx: int = rng.randi_range(0, rooms.size() - 1)
		if a_idx != b_idx:
			_carve_corridor(out, chunk_size, _rect_center(rooms[a_idx]), _rect_center(rooms[b_idx]), rng, max_corridor_width)

	# 7.5. Dead-end stubs: short corridors that branch off main paths into walls
	# and terminate. Makes the layout feel mazey without breaking connectivity.
	if rng.randf() < _DEAD_END_PROBABILITY:
		_carve_dead_ends(out, chunk_size, rng, rooms)

	# 8. Continuous global utility lines spanning boundaries.
	_draw_global_conduits(out, chunk_size, chunk_coord, site_seed)

	# 9. Floor variants & catwalk conversion.
	var base_x: int = chunk_coord.x * chunk_size
	var base_y: int = chunk_coord.y * chunk_size
	for ly in chunk_size:
		for lx in chunk_size:
			var idx: int = ly * chunk_size + lx
			if out[idx] != TILE_FLOOR:
				continue

			# Check if this floor tile is adjacent to a deep void.
			var is_catwalk: bool = false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = lx + dx
					var ny: int = ly + dy
					if nx >= 0 and nx < chunk_size and ny >= 0 and ny < chunk_size:
						if out[ny * chunk_size + nx] == TILE_VOID:
							is_catwalk = true
							break
				if is_catwalk:
					break

			if is_catwalk:
				# Use steel-conduit grating for catwalk safety platforms.
				out[idx] = TILE_CONDUIT if rng.randf() > 0.25 else TILE_RUST
				continue

			var floor_noise: float = noise.get_noise_2d(base_x + lx, base_y + ly)
			var detail_noise: float = noise.get_noise_2d((base_x + lx) * 2.1, (base_y + ly) * 2.1)
			if detail_noise > conduit_threshold:
				out[idx] = TILE_CONDUIT
			elif floor_noise < rust_threshold:
				out[idx] = TILE_RUST
			elif floor_noise > debris_threshold:
				out[idx] = TILE_DEBRIS

	# 10. Room utility taps.
	for room in rooms:
		_place_room_outlets(out, chunk_size, room, rng)

	# 11. Rare mineral veins and structural core machinery.
	_service_core_pass(out, chunk_size, noise, base_x, base_y, service_threshold, rich_threshold)

	# 12. Rare unstable transport pads in open spaces.
	_teleporter_pass(out, chunk_size, noise, base_x, base_y)


static func tile_color(t: int) -> Color:
	match t:
		TILE_FLOOR:  return Color(0.22, 0.24, 0.28)
		TILE_WALL:   return Color(0.55, 0.55, 0.58)
		TILE_DEBRIS: return Color(0.35, 0.30, 0.25)
		TILE_VOID:   return Color(0.06, 0.06, 0.09)
		TILE_OUTLET: return Color(0.25, 0.9, 0.85)
		TILE_SERVICE_CORE: return Color(0.38, 0.55, 0.95)
		TILE_CONDUIT: return Color(0.18, 0.34, 0.42)
		TILE_RUST: return Color(0.42, 0.18, 0.12)
		TILE_RICH_WALL: return Color(0.46, 0.42, 0.62)
		TILE_TELEPORTER: return Color(0.15, 0.92, 1.0)
	return Color.MAGENTA


static func tile_name(t: int) -> String:
	match t:
		TILE_FLOOR: return "floor"
		TILE_WALL: return "wall"
		TILE_DEBRIS: return "debris"
		TILE_VOID: return "void"
		TILE_OUTLET: return "outlet"
		TILE_SERVICE_CORE: return "service core"
		TILE_CONDUIT: return "conduit floor"
		TILE_RUST: return "rust sludge"
		TILE_RICH_WALL: return "rich wall"
		TILE_TELEPORTER: return "teleporter"
		_: return "unknown"


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


static func _place_rooms(
	rng: RandomNumberGenerator,
	chunk_size: int,
	room_t_min: int,
	room_t_max: int,
	room_min_size: int,
	room_max_size: int,
	room_attempts: int
) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	var target: int = rng.randi_range(room_t_min, room_t_max)
	for _attempt in room_attempts:
		if rooms.size() >= target:
			break
		var w: int = rng.randi_range(room_min_size, room_max_size)
		var h: int = rng.randi_range(room_min_size, room_max_size)
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


static func _carve_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
	zone: int,
) -> void:
	var style: int = rng.randi_range(0, 5)

	# Adjust style tendencies depending on the structural zone context
	if zone == 1: # Industrial Core
		if rng.randf() < 0.6:
			style = 5 # machinery core
	elif zone == 2: # Habitation
		style = rng.randi_range(0, 4) # Avoid heavy machine cores, favor clean variants
	elif zone == 3: # Lithic Vault
		style = 0 # Favor basic rectangles to fit within constraints

	match style:
		0:
			_fill_rect(out, chunk_size, room, TILE_FLOOR)
		1:
			_carve_chamfer_room(out, chunk_size, room, rng)
		2:
			_carve_l_room(out, chunk_size, room, rng)
		3:
			_carve_cross_room(out, chunk_size, room, rng)
		4:
			_carve_bay_room(out, chunk_size, room, rng)
		_:
			_carve_machinery_room(out, chunk_size, room, rng)

	# Add support columns in sufficiently large rooms
	if style != 5:
		_add_pillars(out, chunk_size, room, rng, zone)

	var center: Vector2i = _rect_center(room)
	out[center.y * chunk_size + center.x] = TILE_FLOOR


static func _carve_chamfer_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var cut_limit: int = maxi(1, int(float(mini(room.size.x, room.size.y)) / 3.0))
	var cut: int = rng.randi_range(1, mini(3, cut_limit))
	for ly in range(room.position.y, room.position.y + room.size.y):
		for lx in range(room.position.x, room.position.x + room.size.x):
			var left: int = lx - room.position.x
			var right: int = room.position.x + room.size.x - 1 - lx
			var top: int = ly - room.position.y
			var bottom: int = room.position.y + room.size.y - 1 - ly
			var corner_cut: bool = (left + top < cut) \
				or (right + top < cut) \
				or (left + bottom < cut) \
				or (right + bottom < cut)
			if not corner_cut:
				out[ly * chunk_size + lx] = TILE_FLOOR


static func _carve_l_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var min_vertical_w: int = maxi(2, int(float(room.size.x) / 3.0))
	var min_horizontal_h: int = maxi(2, int(float(room.size.y) / 3.0))
	var vertical_w: int = rng.randi_range(min_vertical_w, maxi(2, room.size.x - 1))
	var horizontal_h: int = rng.randi_range(min_horizontal_h, maxi(2, room.size.y - 1))
	var left_side: bool = rng.randi() % 2 == 0
	var top_side: bool = rng.randi() % 2 == 0
	var vertical_x: int = room.position.x if left_side else room.position.x + room.size.x - vertical_w
	var horizontal_y: int = room.position.y if top_side else room.position.y + room.size.y - horizontal_h
	_fill_rect(out, chunk_size, Rect2i(vertical_x, room.position.y, vertical_w, room.size.y), TILE_FLOOR)
	_fill_rect(out, chunk_size, Rect2i(room.position.x, horizontal_y, room.size.x, horizontal_h), TILE_FLOOR)


static func _carve_cross_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var bar_w_min: int = maxi(2, int(float(room.size.x) / 3.0))
	var bar_h_min: int = maxi(2, int(float(room.size.y) / 3.0))
	var bar_w_max: int = maxi(2, int(float(room.size.x) / 2.0) + 1)
	var bar_h_max: int = maxi(2, int(float(room.size.y) / 2.0) + 1)
	var bar_w: int = rng.randi_range(bar_w_min, bar_w_max)
	var bar_h: int = rng.randi_range(bar_h_min, bar_h_max)
	var center: Vector2i = _rect_center(room)
	var x0: int = clampi(
		center.x - int(float(bar_w) / 2.0),
		room.position.x,
		room.position.x + room.size.x - bar_w,
	)
	var y0: int = clampi(
		center.y - int(float(bar_h) / 2.0),
		room.position.y,
		room.position.y + room.size.y - bar_h,
	)
	_fill_rect(out, chunk_size, Rect2i(x0, room.position.y, bar_w, room.size.y), TILE_FLOOR)
	_fill_rect(out, chunk_size, Rect2i(room.position.x, y0, room.size.x, bar_h), TILE_FLOOR)


static func _carve_bay_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var inset: int = rng.randi_range(1, 2)
	var core := Rect2i(
		room.position + Vector2i(inset, inset),
		room.size - Vector2i(inset * 2, inset * 2),
	)
	if core.size.x < 2 or core.size.y < 2:
		_fill_rect(out, chunk_size, room, TILE_FLOOR)
		return
	_fill_rect(out, chunk_size, core, TILE_FLOOR)
	var bay_count: int = rng.randi_range(2, 4)
	for _i in bay_count:
		var side: int = rng.randi_range(0, 3)
		if side < 2:
			var bay_w: int = rng.randi_range(2, maxi(2, int(float(room.size.x) / 2.0)))
			var x: int = rng.randi_range(room.position.x, room.position.x + room.size.x - bay_w)
			var y: int = room.position.y if side == 0 else room.position.y + room.size.y - inset
			_fill_rect(out, chunk_size, Rect2i(x, y, bay_w, inset + 1), TILE_FLOOR)
		else:
			var bay_h: int = rng.randi_range(2, maxi(2, int(float(room.size.y) / 2.0)))
			var x: int = room.position.x if side == 2 else room.position.x + room.size.x - inset
			var y: int = rng.randi_range(room.position.y, room.position.y + room.size.y - bay_h)
			_fill_rect(out, chunk_size, Rect2i(x, y, inset + 1, bay_h), TILE_FLOOR)


## Carves an industrial chamber layout centered around heavy machinery housings.
static func _carve_machinery_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	_fill_rect(out, chunk_size, room, TILE_FLOOR)
	if room.size.x >= 6 and room.size.y >= 6:
		var core_w: int = rng.randi_range(2, room.size.x - 4)
		var core_h: int = rng.randi_range(2, room.size.y - 4)
		var cx: int = room.position.x + (room.size.x - core_w) / 2
		var cy: int = room.position.y + (room.size.y - core_h) / 2
		var core_rect := Rect2i(cx, cy, core_w, core_h)
		_fill_rect(out, chunk_size, core_rect, TILE_SERVICE_CORE)

		# Edge outlets on the machinery block
		if rng.randf() < 0.8:
			out[cy * chunk_size + cx] = TILE_OUTLET


## Injects structured concrete columns inside larger cavernous spaces.
static func _add_pillars(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
	zone: int,
) -> void:
	if room.size.x < 7 or room.size.y < 7:
		return

	# Determine spacing pattern based on the structural style
	var spacing: int = 3
	if zone == 4: # Structural Grid uses strict architectural spacing
		spacing = 3
	else:
		spacing = rng.randi_range(3, 4)

	for y in range(room.position.y + 2, room.position.y + room.size.y - 2, spacing):
		for x in range(room.position.x + 2, room.position.x + room.size.x - 2, spacing):
			var idx: int = y * chunk_size + x
			if out[idx] == TILE_FLOOR:
				out[idx] = TILE_WALL


static func _place_room_outlets(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var count: int = rng.randi_range(0, 1)
	var placed: Dictionary = {}
	var min_x: int = room.position.x
	var max_x: int = room.position.x + room.size.x - 1
	var min_y: int = room.position.y
	var max_y: int = room.position.y + room.size.y - 1
	for _i in count:
		for _attempt in 8:
			var x: int = rng.randi_range(min_x, max_x)
			var y: int = rng.randi_range(min_y, max_y)
			var cell := Vector2i(x, y)
			if placed.has(cell):
				continue
			var idx: int = y * chunk_size + x
			if out[idx] != TILE_FLOOR and out[idx] != TILE_DEBRIS:
				continue
			placed[cell] = true
			out[idx] = TILE_OUTLET
			break


static func _carve_corridor(
	out: PackedInt32Array,
	chunk_size: int,
	from: Vector2i,
	to: Vector2i,
	rng: RandomNumberGenerator,
	max_width: int,
) -> void:
	var width: int = _corridor_width(rng, max_width)
	var style: int = rng.randi_range(0, 3)
	if style == 0:
		_carve_l(out, chunk_size, from, to, rng, width)
	elif style == 1 and from.x != to.x and from.y != to.y:
		var mid_x: int = rng.randi_range(mini(from.x, to.x), maxi(from.x, to.x))
		_carve_h(out, chunk_size, from.x, mid_x, from.y, width)
		_carve_v(out, chunk_size, from.y, to.y, mid_x, width)
		_carve_h(out, chunk_size, mid_x, to.x, to.y, width)
	elif style == 2 and from.x != to.x and from.y != to.y:
		var mid_y: int = rng.randi_range(mini(from.y, to.y), maxi(from.y, to.y))
		_carve_v(out, chunk_size, from.y, mid_y, from.x, width)
		_carve_h(out, chunk_size, from.x, to.x, mid_y, width)
		_carve_v(out, chunk_size, mid_y, to.y, to.x, width)
	else:
		_carve_l(out, chunk_size, from, to, rng, width)


static func _corridor_width(rng: RandomNumberGenerator, max_width: int) -> int:
	if max_width <= 1:
		return 1
	var roll: float = rng.randf()
	if max_width >= 3 and roll < 0.08:
		return 3
	if max_width >= 2 and roll < 0.28:
		return 2
	return 1


static func _carve_l(
	out: PackedInt32Array,
	chunk_size: int,
	from: Vector2i,
	to: Vector2i,
	rng: RandomNumberGenerator,
	width: int,
) -> void:
	if rng.randi() % 2 == 0:
		_carve_h(out, chunk_size, from.x, to.x, from.y, width)
		_carve_v(out, chunk_size, from.y, to.y, to.x, width)
	else:
		_carve_v(out, chunk_size, from.y, to.y, from.x, width)
		_carve_h(out, chunk_size, from.x, to.x, to.y, width)


static func _carve_h(
	out: PackedInt32Array,
	chunk_size: int,
	x0: int,
	x1: int,
	y: int,
	width: int = 1,
) -> void:
	if y < 0 or y >= chunk_size:
		return
	var lo: int = mini(x0, x1)
	var hi: int = maxi(x0, x1)
	lo = clampi(lo, 0, chunk_size - 1)
	hi = clampi(hi, 0, chunk_size - 1)
	for x in range(lo, hi + 1):
		_carve_disc(out, chunk_size, Vector2i(x, y), width)


static func _carve_v(
	out: PackedInt32Array,
	chunk_size: int,
	y0: int,
	y1: int,
	x: int,
	width: int = 1,
) -> void:
	if x < 0 or x >= chunk_size:
		return
	var lo: int = mini(y0, y1)
	var hi: int = maxi(y0, y1)
	lo = clampi(lo, 0, chunk_size - 1)
	hi = clampi(hi, 0, chunk_size - 1)
	for y in range(lo, hi + 1):
		_carve_disc(out, chunk_size, Vector2i(x, y), width)


static func _carve_disc(out: PackedInt32Array, chunk_size: int, center: Vector2i, width: int) -> void:
	var radius: int = maxi(0, width - 1)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if absi(dx) + absi(dy) > radius:
				continue
			var x: int = center.x + dx
			var y: int = center.y + dy
			if x < 0 or x >= chunk_size or y < 0 or y >= chunk_size:
				continue
			var idx: int = y * chunk_size + x
			if out[idx] != TILE_VOID:
				out[idx] = TILE_FLOOR


static func _rect_center(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


## Carves a small number of short dead-end stubs branching from existing floor
## tiles into surrounding walls. Increases the mazey "many-pockets" feel
## without breaking connectivity.
static func _carve_dead_ends(
	out: PackedInt32Array,
	chunk_size: int,
	rng: RandomNumberGenerator,
	rooms: Array[Rect2i],
) -> void:
	if rooms.is_empty():
		return
	var count: int = rng.randi_range(_DEAD_END_COUNT_MIN, _DEAD_END_COUNT_MAX)
	const DIRS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for _i in range(count):
		# Pick a random floor cell as the stub origin.
		var origin: Vector2i = _random_floor_cell(out, chunk_size, rng)
		if origin.x < 0:
			continue
		var dir: Vector2i = DIRS[rng.randi() % DIRS.size()]
		var length: int = rng.randi_range(_DEAD_END_MIN_LENGTH, _DEAD_END_MAX_LENGTH)
		var pos: Vector2i = origin
		for _step in range(length):
			pos += dir
			if pos.x < _EDGE_MARGIN or pos.x >= chunk_size - _EDGE_MARGIN \
					or pos.y < _EDGE_MARGIN or pos.y >= chunk_size - _EDGE_MARGIN:
				break
			var idx: int = pos.y * chunk_size + pos.x
			# Only burrow through walls.
			if out[idx] != TILE_WALL:
				break
			out[idx] = TILE_FLOOR
			# Small chance to add a 1-tile dangling pocket at the very end.
		# Optional pocket at the tip.
		if rng.randf() < 0.45:
			var perp := Vector2i(-dir.y, dir.x)
			var pocket: Vector2i = pos + perp
			if pocket.x >= _EDGE_MARGIN and pocket.x < chunk_size - _EDGE_MARGIN \
					and pocket.y >= _EDGE_MARGIN and pocket.y < chunk_size - _EDGE_MARGIN:
				var p_idx: int = pocket.y * chunk_size + pocket.x
				if out[p_idx] == TILE_WALL:
					out[p_idx] = TILE_FLOOR


static func _random_floor_cell(
	out: PackedInt32Array,
	chunk_size: int,
	rng: RandomNumberGenerator,
) -> Vector2i:
	for _attempt in 24:
		var x: int = rng.randi_range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN - 1)
		var y: int = rng.randi_range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN - 1)
		var idx: int = y * chunk_size + x
		if out[idx] == TILE_FLOOR:
			# Prefer cells with at least one wall neighbour so the stub burrows in.
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + off.x
				var ny: int = y + off.y
				if nx < 0 or nx >= chunk_size or ny < 0 or ny >= chunk_size:
					continue
				if out[ny * chunk_size + nx] == TILE_WALL:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


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


static func _void_pass(
	out: PackedInt32Array,
	chunk_size: int,
	rng: RandomNumberGenerator,
	void_min: int,
	void_max: int,
	void_rad_min: int,
	void_rad_max: int,
) -> void:
	if void_max <= 0:
		return # Skip void generation (e.g., inside Habitation Zones)

	var snapshot: PackedInt32Array = out.duplicate()
	var cluster_count: int = rng.randi_range(void_min, void_max)
	for _cluster in cluster_count:
		var seed: Vector2i = _pick_deep_wall(snapshot, chunk_size, rng)
		if seed.x < 0:
			return
		var rx: int = rng.randi_range(void_rad_min, void_rad_max)
		var ry: int = rng.randi_range(void_rad_min, void_rad_max)
		_carve_void_blob(out, snapshot, chunk_size, seed, rx, ry, rng)


static func _pick_deep_wall(
	snapshot: PackedInt32Array,
	chunk_size: int,
	rng: RandomNumberGenerator,
) -> Vector2i:
	for _attempt in 32:
		var cell := Vector2i(
			rng.randi_range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN - 1),
			rng.randi_range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN - 1),
		)
		if _is_deep_wall(snapshot, chunk_size, cell):
			return cell
	return Vector2i(-1, -1)


static func _carve_void_blob(
	out: PackedInt32Array,
	snapshot: PackedInt32Array,
	chunk_size: int,
	center: Vector2i,
	radius_x: int,
	radius_y: int,
	rng: RandomNumberGenerator,
) -> void:
	for y in range(center.y - radius_y, center.y + radius_y + 1):
		for x in range(center.x - radius_x, center.x + radius_x + 1):
			var cell := Vector2i(x, y)
			if not _is_deep_wall(snapshot, chunk_size, cell):
				continue
			var nx: float = float(x - center.x) / float(radius_x)
			var ny: float = float(y - center.y) / float(radius_y)
			var edge_jitter: float = rng.randf_range(-0.18, 0.18)
			if nx * nx + ny * ny <= 1.0 + edge_jitter:
				out[y * chunk_size + x] = TILE_VOID
	var tendrils: int = rng.randi_range(1, 3)
	for _i in tendrils:
		var pos: Vector2i = center
		var steps: int = rng.randi_range(2, radius_x + radius_y)
		for _step in steps:
			pos += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
			if _is_deep_wall(snapshot, chunk_size, pos):
				out[pos.y * chunk_size + pos.x] = TILE_VOID


static func _is_deep_wall(snapshot: PackedInt32Array, chunk_size: int, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= chunk_size or cell.y < 0 or cell.y >= chunk_size:
		return false
	var idx: int = cell.y * chunk_size + cell.x
	if snapshot[idx] != TILE_WALL:
		return false
	var wall_count: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = cell.x + dx
			var ny: int = cell.y + dy
			if nx < 0 or nx >= chunk_size or ny < 0 or ny >= chunk_size:
				wall_count += 1
				continue
			if snapshot[ny * chunk_size + nx] == TILE_WALL:
				wall_count += 1
	return wall_count >= _VOID_NEIGHBOUR_THRESHOLD


## Renders continuous global pipelines passing through chunk limits deterministically.
static func _draw_global_conduits(
	out: PackedInt32Array,
	chunk_size: int,
	chunk_coord: Vector2i,
	site_seed: int,
) -> void:
	var rng := RandomNumberGenerator.new()

	# Horizontal global pipeline
	rng.seed = hash([site_seed, chunk_coord.y, "global_h_conduit"])
	if rng.randf() < 0.22:
		var y: int = rng.randi_range(_EDGE_MARGIN + 2, chunk_size - _EDGE_MARGIN - 3)
		for x in chunk_size:
			var idx: int = y * chunk_size + x
			if out[idx] == TILE_WALL:
				out[idx] = TILE_CONDUIT

	# Vertical global pipeline
	rng.seed = hash([site_seed, chunk_coord.x, "global_v_conduit"])
	if rng.randf() < 0.22:
		var x: int = rng.randi_range(_EDGE_MARGIN + 2, chunk_size - _EDGE_MARGIN - 3)
		for y in chunk_size:
			var idx: int = y * chunk_size + x
			if out[idx] == TILE_WALL:
				out[idx] = TILE_CONDUIT


static func _service_core_pass(
	out: PackedInt32Array,
	chunk_size: int,
	noise: FastNoiseLite,
	base_x: int,
	base_y: int,
	service_threshold: float,
	rich_threshold: float,
) -> void:
	for ly in chunk_size:
		for lx in chunk_size:
			var idx: int = ly * chunk_size + lx
			if out[idx] != TILE_WALL:
				continue
			var mineral_noise: float = noise.get_noise_2d((base_x + lx) * 1.9, (base_y + ly) * 1.9)
			if mineral_noise > rich_threshold:
				out[idx] = TILE_RICH_WALL
			if noise.get_noise_2d((base_x + lx) * 2.7, (base_y + ly) * 2.7) > service_threshold:
				out[idx] = TILE_SERVICE_CORE


static func _teleporter_pass(
	out: PackedInt32Array,
	chunk_size: int,
	noise: FastNoiseLite,
	base_x: int,
	base_y: int,
) -> void:
	for ly in chunk_size:
		for lx in chunk_size:
			var idx: int = ly * chunk_size + lx
			if out[idx] != TILE_FLOOR and out[idx] != TILE_CONDUIT:
				continue
			var value: float = noise.get_noise_2d((base_x + lx) * 3.7 + 171.0, (base_y + ly) * 3.7 - 89.0)
			if value > _TELEPORTER_NOISE_THRESHOLD:
				out[idx] = TILE_TELEPORTER
