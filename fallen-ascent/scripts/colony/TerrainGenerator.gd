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
## 6=conduit floor, 7=rust sludge, 8=rich wall, 9=teleporter, 10=deep water,
## 11=shallow water, 12=puddle, 13=deep acid, 14=shallow acid, 15=acid puddle.

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
const TILE_WATER: int = 10
const TILE_WATER_SHALLOW: int = 11
const TILE_WATER_PUDDLE: int = 12
const TILE_ACID: int = 13
const TILE_ACID_SHALLOW: int = 14
const TILE_ACID_PUDDLE: int = 15

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
const _RUST_NOISE_THRESHOLD: float = -0.25
const _WATER_NOISE_THRESHOLD: float = -0.72
const _SERVICE_CORE_NOISE_THRESHOLD: float = 0.80
const _RICH_WALL_NOISE_THRESHOLD: float = 0.76
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

# Macro-Structure Probability (Concept 5)
const _MACRO_STRUCTURE_PROBABILITY: float = 0.15


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
	var water_threshold: float = _WATER_NOISE_THRESHOLD
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
			water_threshold = -0.68

		1: # The Industrial Core (Dense machinery / Conduits)
			room_target_min = 3
			room_target_max = 5
			room_min_size = 6
			room_max_size = 12
			void_min = 0
			void_max = 1
			service_threshold = 0.72
			conduit_threshold = 0.40 # Heavy floor lines
			water_threshold = -0.78

		2: # Habitation Blocks (Compartmentalized chambers)
			room_target_min = 4
			room_target_max = 7
			room_min_size = 4
			room_max_size = 8
			void_min = 0
			void_max = 0 # No hazard voids in residential blocks
			shortcut_prob = 0.15
			water_threshold = -0.82

		3: # Lithic Vault (Dense stone / Resource veins)
			room_target_min = 1
			room_target_max = 3
			room_min_size = 3
			room_max_size = 5
			void_min = 1
			void_max = 3
			rich_threshold = 0.66
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

	# 4. Carve layout (Standard rooms OR Single Macro-Structure)
	var is_macro_chunk: bool = (rng.randf() < _MACRO_STRUCTURE_PROBABILITY) and (zone != 2)
	var rooms: Array[Rect2i] = []

	if is_macro_chunk:
		# CONCEPT 5: Generates a monolithic structure spanning the chunk
		_carve_macro_structure(out, chunk_size, doors, rng, zone)
	else:
		# Standard Room layout
		rooms = _place_rooms(
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
			# Layered water field: lake basins (low-frequency depressions),
			# rivers (thin ridge bands), and stray puddles (high-frequency
			# spots). Each contributes its own depth band, and the deepest
			# kind wins per cell so shores transition deep -> shallow -> puddle.
			var water_kind: int = _water_kind_at(
				noise,
				base_x + lx,
				base_y + ly,
				zone,
				water_threshold,
				lx,
				ly,
				chunk_size,
			)
			if water_kind >= 0:
				out[idx] = water_kind
				continue
			# Acid is much rarer and only fires on otherwise dry cells, so
			# water bodies stay coherent while acid takes the leftover.
			var acid_kind: int = _acid_kind_at(
				noise,
				base_x + lx,
				base_y + ly,
				zone,
				lx,
				ly,
				chunk_size,
			)
			if acid_kind >= 0:
				out[idx] = acid_kind
				continue
			if detail_noise > conduit_threshold:
				out[idx] = TILE_CONDUIT
			elif floor_noise < rust_threshold:
				out[idx] = TILE_RUST
			elif floor_noise > debris_threshold:
				out[idx] = TILE_DEBRIS

	# 10. Room utility taps (Only applicable to room arrays)
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
		TILE_WATER: return Color(0.05, 0.28, 0.55)
		TILE_WATER_SHALLOW: return Color(0.18, 0.55, 0.62)
		TILE_WATER_PUDDLE: return Color(0.38, 0.42, 0.38)
		TILE_ACID: return Color(0.12, 0.38, 0.10)
		TILE_ACID_SHALLOW: return Color(0.30, 0.62, 0.18)
		TILE_ACID_PUDDLE: return Color(0.46, 0.66, 0.22)
	return Color.MAGENTA


static func tile_name(t: int) -> String:
	match t:
		TILE_FLOOR: return "floor"
		TILE_WALL: return "wall"
		TILE_DEBRIS: return "debris"
		TILE_VOID: return "void"
		TILE_OUTLET: return "outlet"
		TILE_SERVICE_CORE: return "derelict core"
		TILE_CONDUIT: return "conduit floor"
		TILE_RUST: return "rust sludge"
		TILE_RICH_WALL: return "plated wall"
		TILE_TELEPORTER: return "teleporter"
		TILE_WATER: return "deep water"
		TILE_WATER_SHALLOW: return "shallow water"
		TILE_WATER_PUDDLE: return "puddle"
		TILE_ACID: return "deep acid"
		TILE_ACID_SHALLOW: return "shallow acid"
		TILE_ACID_PUDDLE: return "acid puddle"
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
	var style: int = _pick_room_style(rng, zone, room)

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
		5:
			_carve_machinery_room(out, chunk_size, room, rng)
		6:
			_carve_oval_room(out, chunk_size, room, rng)
		7:
			_carve_triangle_room(out, chunk_size, room, rng)
		8:
			_carve_donut_room(out, chunk_size, room, rng)
		_:
			_carve_jagged_room(out, chunk_size, room, rng)

	# CONCEPT 2: Incorporate brutalist buttresses along the interior walls of large rooms
	if style in [0, 1, 3, 4, 5]:
		_add_buttresses_to_room(out, chunk_size, room, rng)

	# Add support columns in sufficiently large rooms
	if style != 5:
		_add_pillars(out, chunk_size, room, rng, zone)

	var center: Vector2i = _rect_center(room)
	out[center.y * chunk_size + center.x] = TILE_FLOOR


static func _pick_room_style(rng: RandomNumberGenerator, zone: int, room: Rect2i) -> int:
	var styles: Array[int] = [0, 1, 2, 3, 4, 6, 7, 9]
	if room.size.x >= 6 and room.size.y >= 6:
		styles.append(8)
	if zone == 1 and room.size.x >= 6 and room.size.y >= 6:
		styles.append(5)
		styles.append(5)
		styles.append(9)
	elif zone == 2:
		styles.append(6)
		styles.append(7)
	elif zone == 3:
		styles = [0, 1, 6, 7, 9]
	elif zone == 4:
		styles.append(3)
		styles.append(8)
	return int(styles[rng.randi() % styles.size()])


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
	var bar_w_max: int = maxi(2, int(float(room.size.y) / 2.0) + 1)
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
		_fill_rect(out, chunk_size, core_rect, TILE_WALL)
		var core_count: int = rng.randi_range(1, 2)
		var placed: Dictionary = {}
		for _i in core_count:
			for _attempt in 8:
				var cell := Vector2i(
					rng.randi_range(core_rect.position.x, core_rect.position.x + core_rect.size.x - 1),
					rng.randi_range(core_rect.position.y, core_rect.position.y + core_rect.size.y - 1),
				)
				if placed.has(cell) or _has_special_neighbor(out, chunk_size, cell):
					continue
				placed[cell] = true
				out[cell.y * chunk_size + cell.x] = TILE_SERVICE_CORE
				break

		# Edge outlets on the machinery block
		if rng.randf() < 0.8:
			out[cy * chunk_size + cx] = TILE_OUTLET


static func _carve_oval_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var center := Vector2(
		float(room.position.x) + (float(room.size.x) - 1.0) * 0.5,
		float(room.position.y) + (float(room.size.y) - 1.0) * 0.5,
	)
	var rx: float = maxf(1.0, float(room.size.x) * 0.5)
	var ry: float = maxf(1.0, float(room.size.y) * 0.5)
	for ly in range(room.position.y, room.position.y + room.size.y):
		for lx in range(room.position.x, room.position.x + room.size.x):
			var nx: float = (float(lx) - center.x) / rx
			var ny: float = (float(ly) - center.y) / ry
			var rough: float = rng.randf_range(-0.08, 0.08)
			if nx * nx + ny * ny <= 1.0 + rough:
				out[ly * chunk_size + lx] = TILE_FLOOR


static func _carve_triangle_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var orientation: int = rng.randi_range(0, 3)
	for ly in range(room.position.y, room.position.y + room.size.y):
		for lx in range(room.position.x, room.position.x + room.size.x):
			var tx: float = float(lx - room.position.x) / maxf(1.0, float(room.size.x - 1))
			var ty: float = float(ly - room.position.y) / maxf(1.0, float(room.size.y - 1))
			var inside: bool = false
			match orientation:
				0:
					inside = absf(tx - 0.5) <= ty * 0.55 + 0.12
				1:
					inside = absf(tx - 0.5) <= (1.0 - ty) * 0.55 + 0.12
				2:
					inside = absf(ty - 0.5) <= tx * 0.55 + 0.12
				_:
					inside = absf(ty - 0.5) <= (1.0 - tx) * 0.55 + 0.12
			if inside:
				out[ly * chunk_size + lx] = TILE_FLOOR


static func _carve_donut_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	if room.size.x < 6 or room.size.y < 6:
		_carve_oval_room(out, chunk_size, room, rng)
		return
	_carve_oval_room(out, chunk_size, room, rng)
	var inset: int = rng.randi_range(2, 3)
	var inner := Rect2i(
		room.position + Vector2i(inset, inset),
		room.size - Vector2i(inset * 2, inset * 2),
	)
	if inner.size.x <= 1 or inner.size.y <= 1:
		return
	var center := Vector2(
		float(inner.position.x) + (float(inner.size.x) - 1.0) * 0.5,
		float(inner.position.y) + (float(inner.size.y) - 1.0) * 0.5,
	)
	var rx: float = maxf(1.0, float(inner.size.x) * 0.5)
	var ry: float = maxf(1.0, float(inner.size.y) * 0.5)
	for ly in range(inner.position.y, inner.position.y + inner.size.y):
		for lx in range(inner.position.x, inner.position.x + inner.size.x):
			var nx: float = (float(lx) - center.x) / rx
			var ny: float = (float(ly) - center.y) / ry
			if nx * nx + ny * ny <= 1.0:
				out[ly * chunk_size + lx] = TILE_WALL


static func _carve_jagged_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	var lobes: int = rng.randi_range(2, 4)
	for _i in lobes:
		var w: int = rng.randi_range(maxi(2, int(float(room.size.x) / 3.0)), maxi(2, room.size.x))
		var h: int = rng.randi_range(maxi(2, int(float(room.size.y) / 3.0)), maxi(2, room.size.y))
		var x: int = rng.randi_range(room.position.x, room.position.x + room.size.x - w)
		var y: int = rng.randi_range(room.position.y, room.position.y + room.size.y - h)
		var lobe := Rect2i(x, y, w, h)
		if rng.randf() < 0.55:
			_carve_oval_room(out, chunk_size, lobe, rng)
		else:
			_fill_rect(out, chunk_size, lobe, TILE_FLOOR)
	var center: Vector2i = _rect_center(room)
	for ly in range(room.position.y, room.position.y + room.size.y):
		for lx in range(room.position.x, room.position.x + room.size.x):
			if out[ly * chunk_size + lx] == TILE_FLOOR and rng.randf() < 0.12:
				_carve_corridor(out, chunk_size, center, Vector2i(lx, ly), rng, 1)


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


## CONCEPT 2: Projects heavy load-bearing wall supports inward along rectangular margins.
static func _add_buttresses_to_room(
	out: PackedInt32Array,
	chunk_size: int,
	room: Rect2i,
	rng: RandomNumberGenerator,
) -> void:
	if room.size.x < 6 or room.size.y < 6:
		return

	# Protrude inward on North and South walls
	for lx in range(room.position.x + 2, room.position.x + room.size.x - 2, 3):
		if rng.randf() < 0.8:
			var n_idx: int = (room.position.y) * chunk_size + lx
			var s_idx: int = (room.position.y + room.size.y - 1) * chunk_size + lx
			
			# Check immediate inner neighbors to safely place wall protrusion
			if out[n_idx + chunk_size] == TILE_FLOOR:
				out[n_idx + chunk_size] = TILE_WALL
			if out[s_idx - chunk_size] == TILE_FLOOR:
				out[s_idx - chunk_size] = TILE_WALL

	# Protrude inward on West and East walls
	for ly in range(room.position.y + 2, room.position.y + room.size.y - 2, 3):
		if rng.randf() < 0.8:
			var w_idx: int = ly * chunk_size + room.position.x
			var e_idx: int = ly * chunk_size + (room.position.x + room.size.x - 1)
			
			if out[w_idx + 1] == TILE_FLOOR:
				out[w_idx + 1] = TILE_WALL
			if out[e_idx - 1] == TILE_FLOOR:
				out[e_idx - 1] = TILE_WALL


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

	# CONCEPT 4: Chance to generate continuous linear sine-wave chasms instead of simple blobs
	if rng.randf() < 0.35:
		_carve_linear_chasm(out, chunk_size, rng)
		return

	var snapshot: PackedInt32Array = out.duplicate()
	var cluster_count: int = rng.randi_range(void_min, void_max)
	for _cluster in cluster_count:
		var seed: Vector2i = _pick_deep_wall(snapshot, chunk_size, rng)
		if seed.x < 0:
			return
		var rx: int = rng.randi_range(void_rad_min, void_rad_max)
		var ry: int = rng.randi_range(void_rad_min, void_rad_max)
		_carve_void_blob(out, snapshot, chunk_size, seed, rx, ry, rng)


## CONCEPT 4: Carves a wide, winding linear canyon across the chunk boundaries
static func _carve_linear_chasm(
	out: PackedInt32Array,
	chunk_size: int,
	rng: RandomNumberGenerator,
) -> void:
	var horizontal: bool = rng.randi() % 2 == 0
	var start_pos: int = rng.randi_range(_EDGE_MARGIN + 4, chunk_size - _EDGE_MARGIN - 5)
	var amplitude: float = rng.randf_range(2.0, 5.0)
	var frequency: float = rng.randf_range(0.12, 0.26)
	var width: int = rng.randi_range(3, 5)

	if horizontal:
		for x in range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN):
			var center_y: int = int(float(start_pos) + amplitude * sin(float(x) * frequency))
			for dy in range(-width / 2, width / 2 + 1):
				var y: int = center_y + dy
				if y >= _EDGE_MARGIN and y < chunk_size - _EDGE_MARGIN:
					out[y * chunk_size + x] = TILE_VOID
	else:
		for y in range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN):
			var center_x: int = int(float(start_pos) + amplitude * sin(float(y) * frequency))
			for dx in range(-width / 2, width / 2 + 1):
				var x: int = center_x + dx
				if x >= _EDGE_MARGIN and x < chunk_size - _EDGE_MARGIN:
					out[y * chunk_size + x] = TILE_VOID


## CONCEPT 5: Overwrites typical layout to carve a monolithic, structured geometric facility
static func _carve_macro_structure(
	out: PackedInt32Array,
	chunk_size: int,
	doors: Array[Vector2i],
	rng: RandomNumberGenerator,
	zone: int,
) -> void:
	var style: int = rng.randi_range(0, 2)
	var center := Vector2i(chunk_size / 2, chunk_size / 2)

	match style:
		0: # The Central Monolith (Corridor loop surrounding massive core block)
			var size: int = rng.randi_range(8, chunk_size - 10)
			var half: int = size / 2
			var rect := Rect2i(center.x - half, center.y - half, size, size)

			# Lay a continuous walk path loop surrounding the monolith bounds
			var ring := Rect2i(rect.position - Vector2i(2, 2), rect.size + Vector2i(4, 4))
			for y in range(ring.position.y, ring.position.y + ring.size.y):
				for x in range(ring.position.x, ring.position.x + ring.size.x):
					if x >= _EDGE_MARGIN and x < chunk_size - _EDGE_MARGIN and y >= _EDGE_MARGIN and y < chunk_size - _EDGE_MARGIN:
						out[y * chunk_size + x] = TILE_FLOOR

			# Restore the solid central core monolith
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				for x in range(rect.position.x, rect.position.x + rect.size.x):
					if x >= 0 and x < chunk_size and y >= 0 and y < chunk_size:
						out[y * chunk_size + x] = TILE_WALL

		1: # The Core Cylinder (Outer walkway ring, hollow deep core void)
			var outer_r: float = float(chunk_size) * 0.38
			var inner_r: float = float(chunk_size) * 0.22
			var void_r: float = float(chunk_size) * 0.12

			for y in range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN):
				for x in range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN):
					var dist: float = center.distance_to(Vector2i(x, y))
					if dist <= outer_r and dist > inner_r:
						out[y * chunk_size + x] = TILE_FLOOR
					elif dist <= void_r:
						out[y * chunk_size + x] = TILE_VOID

		2: # Massive Grid Matrix (Rigidly spaced monolithic support pillars)
			var spacing: int = rng.randi_range(4, 6)
			
			# Carve open area first
			for y in range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN):
				for x in range(_EDGE_MARGIN, chunk_size - _EDGE_MARGIN):
					out[y * chunk_size + x] = TILE_FLOOR

			# Set down heavy columns in mathematical increments
			for y in range(_EDGE_MARGIN + 2, chunk_size - _EDGE_MARGIN - 2, spacing):
				for x in range(_EDGE_MARGIN + 2, chunk_size - _EDGE_MARGIN - 2, spacing):
					for dy in range(2):
						for dx in range(2):
							var idx: int = (y + dy) * chunk_size + (x + dx)
							if idx < out.size():
								out[idx] = TILE_WALL

	# Draw explicit corridors from each outer doorway to the center to secure traversability
	for door in doors:
		out[door.y * chunk_size + door.x] = TILE_FLOOR
		_carve_corridor(out, chunk_size, door, center, rng, 2)


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
			var core_noise: float = noise.get_noise_2d((base_x + lx) * 2.7, (base_y + ly) * 2.7)
			var rare_roll: int = absi(hash([base_x + lx, base_y + ly, "rare_wall"])) % 100
			if core_noise > service_threshold and rare_roll < 18 \
					and _is_local_noise_peak(noise, base_x + lx, base_y + ly, 2.7) \
					and not _has_special_neighbor(out, chunk_size, Vector2i(lx, ly), 2):
				out[idx] = TILE_SERVICE_CORE
				continue
			if mineral_noise > rich_threshold and rare_roll < 24 \
					and _is_local_noise_peak(noise, base_x + lx, base_y + ly, 1.9) \
					and not _has_special_neighbor(out, chunk_size, Vector2i(lx, ly), 2):
				out[idx] = TILE_RICH_WALL


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


static func _has_special_neighbor(
	out: PackedInt32Array,
	chunk_size: int,
	cell: Vector2i,
	radius: int = 1,
) -> bool:
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			if x < 0 or x >= chunk_size or y < 0 or y >= chunk_size:
				continue
			if x == cell.x and y == cell.y:
				continue
			var tile: int = out[y * chunk_size + x]
			if tile == TILE_SERVICE_CORE or tile == TILE_RICH_WALL:
				return true
	return false


static func _is_local_noise_peak(noise: FastNoiseLite, x: int, y: int, scale: float) -> bool:
	var center: float = noise.get_noise_2d(float(x) * scale, float(y) * scale)
	const OFFSETS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for off in OFFSETS:
		var sample: float = noise.get_noise_2d(float(x + off.x) * scale, float(y + off.y) * scale)
		if sample > center:
			return false
	return true


## Returns one of TILE_WATER / TILE_WATER_SHALLOW / TILE_WATER_PUDDLE, or -1
## when the cell is dry. Combines three water sources so the world gets a mix
## of lakes (broad continuous basins), rivers (long thin channels), and stray
## puddles (small isolated spots). Each source is bucketed into deep/shallow/
## puddle bands, then the deepest among them wins. We also keep the legacy
## `floor_noise < water_threshold` branch so existing per-zone tuning still
## modulates the moisture density.
##
## To keep cross-chunk traversal alive, deep water is never placed inside a
## 2-cell margin from a chunk edge (so doorway corridors don't get cut by a
## lake straddling the boundary).
static func _water_kind_at(
	noise: FastNoiseLite,
	wx: int,
	wy: int,
	zone: int,
	water_threshold: float,
	lx: int,
	ly: int,
	chunk_size: int,
) -> int:
	var lake_enabled: bool = true
	var river_enabled: bool = true
	var puddle_enabled: bool = true
	var lake_bias: float = 0.0
	var river_bias: float = 0.0
	var puddle_bias: float = 0.0
	match zone:
		0:  # The Abyss — flooded chasms, ground-water seeps
			lake_bias = 0.02
			river_bias = -0.04
			puddle_bias = 0.01
		1:  # The Industrial Core — coolant puddles only, no open lakes
			lake_enabled = false
			river_bias = -0.12
			puddle_bias = -0.02
		2:  # Habitation Blocks — mostly dry, occasional puddle
			lake_bias = -0.18
			river_bias = -0.14
			puddle_bias = -0.08
		3:  # Lithic Vault — underground aquifers and runoff streams
			lake_bias = -0.02
			river_bias = 0.02
			puddle_bias = -0.02
		4:  # Structural Grid — broad shallow lakes between pillars
			lake_bias = 0.02
			river_bias = -0.10
			puddle_bias = -0.04

	# Threshold scaling so per-zone water_threshold tuning still nudges all
	# bands together (-0.72 → wetter, -0.82 → drier).
	var moisture: float = (-0.72 - water_threshold) * 0.6
	lake_bias -= moisture
	river_bias -= moisture
	puddle_bias -= moisture

	var depth: int = -1  # -1 dry, 0 puddle, 1 shallow, 2 deep

	if lake_enabled:
		# Broad basin: low-frequency noise centred near zero. Negative values
		# are "below water-line".
		var lake_n: float = noise.get_noise_2d(float(wx) * 0.18, float(wy) * 0.18)
		var lake_score: float = -lake_n + lake_bias
		if lake_score > 0.55:
			depth = maxi(depth, 2)
		elif lake_score > 0.45:
			depth = maxi(depth, 1)
		elif lake_score > 0.35:
			depth = maxi(depth, 0)

	if river_enabled:
		# Ridged noise: |n| close to 0 traces zero-crossings, producing
		# long sinuous curves. Tight bands -> deep channel, wider rim ->
		# shallow + puddle, so rivers feel like they actually have shores.
		var river_n: float = noise.get_noise_2d(float(wx) * 0.11 + 941.0, float(wy) * 0.11 - 533.0)
		var river_raw: float = absf(river_n) - river_bias
		if river_raw < 0.01:
			depth = maxi(depth, 2)
		elif river_raw < 0.03:
			depth = maxi(depth, 1)
		elif river_raw < 0.06:
			depth = maxi(depth, 0)

	if puddle_enabled:
		# Higher-frequency speckle for isolated puddles in otherwise dry
		# corridors. Only ever puddle depth, never deep.
		var puddle_n: float = noise.get_noise_2d(float(wx) * 0.55 + 2137.0, float(wy) * 0.55 + 3719.0)
		if puddle_n + puddle_bias > 0.78:
			depth = maxi(depth, 0)

	if depth < 0:
		return -1

	# Keep deep water away from chunk edges so doors / corridor seams stay
	# walkable across chunk boundaries. Shallow/puddle is walkable and fine.
	var edge_margin: int = 2
	if depth == 2 and (
			lx < edge_margin or lx >= chunk_size - edge_margin
			or ly < edge_margin or ly >= chunk_size - edge_margin):
		depth = 1

	match depth:
		2: return TILE_WATER
		1: return TILE_WATER_SHALLOW
		_: return TILE_WATER_PUDDLE


## Returns one of TILE_ACID / TILE_ACID_SHALLOW / TILE_ACID_PUDDLE, or -1 when
## the cell is dry. Mirrors _water_kind_at() but uses rarer thresholds and
## zone-specific bias so acid is genuinely hazardous and uncommon. Decorrelated
## noise offsets keep acid from coinciding with water.
static func _acid_kind_at(
	noise: FastNoiseLite,
	wx: int,
	wy: int,
	zone: int,
	lx: int,
	ly: int,
	chunk_size: int,
) -> int:
	var pool_enabled: bool = true
	var seep_enabled: bool = true
	var splash_enabled: bool = true
	var pool_bias: float = 0.0
	var seep_bias: float = 0.0
	var splash_bias: float = 0.0
	match zone:
		0:  # The Abyss — corrosive seep from above
			pool_bias = -0.04
			seep_bias = -0.02
			splash_bias = -0.02
		1:  # The Industrial Core — coolant breaches, leaking reactors
			pool_bias = 0.01
			seep_bias = -0.04
			splash_bias = 0.01
		2:  # Habitation Blocks — rare, mostly leaky pipes
			pool_enabled = false
			seep_bias = -0.15
			splash_bias = -0.10
		3:  # Lithic Vault — natural acid aquifers
			pool_bias = -0.04
			seep_bias = -0.02
			splash_bias = -0.06
		4:  # Structural Grid — sparse industrial residue
			pool_enabled = false
			seep_enabled = false
			splash_bias = -0.15

	var depth: int = -1  # -1 dry, 0 puddle, 1 shallow, 2 deep

	if pool_enabled:
		var pool_n: float = noise.get_noise_2d(float(wx) * 0.21 + 5021.0, float(wy) * 0.21 - 1873.0)
		var pool_score: float = -pool_n + pool_bias
		# Rarer than water lakes: tighter thresholds.
		if pool_score > 0.65:
			depth = maxi(depth, 2)
		elif pool_score > 0.55:
			depth = maxi(depth, 1)
		elif pool_score > 0.45:
			depth = maxi(depth, 0)

	if seep_enabled:
		var seep_n: float = noise.get_noise_2d(float(wx) * 0.14 - 2273.0, float(wy) * 0.14 + 1607.0)
		var seep_raw: float = absf(seep_n) - seep_bias
		# Acid runs follow ridged noise like rivers, but much thinner.
		if seep_raw < 0.005:
			depth = maxi(depth, 2)
			# Trim to shallow if it might dilute too quickly; we want hazard not pools.
		elif seep_raw < 0.015:
			depth = maxi(depth, 1)
		elif seep_raw < 0.03:
			depth = maxi(depth, 0)

	if splash_enabled:
		var splash_n: float = noise.get_noise_2d(float(wx) * 0.62 - 4093.0, float(wy) * 0.62 + 6173.0)
		if splash_n + splash_bias > 0.85:
			depth = maxi(depth, 0)

	if depth < 0:
		return -1

	# Keep deep acid away from chunk seams.
	var edge_margin: int = 2
	if depth == 2 and (
			lx < edge_margin or lx >= chunk_size - edge_margin
			or ly < edge_margin or ly >= chunk_size - edge_margin):
		depth = 1

	match depth:
		2: return TILE_ACID
		1: return TILE_ACID_SHALLOW
		_: return TILE_ACID_PUDDLE
