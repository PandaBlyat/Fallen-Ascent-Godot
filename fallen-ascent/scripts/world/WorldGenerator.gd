class_name WorldGenerator
extends RefCounted
##
## Deterministic overview-map procgen. Pure functions only — no scene-tree
## side effects. Same `(seed, size)` ALWAYS yields the same SiteData array.
##
## Seed mixing scheme: `site_seed = hash([world_seed, gx, gy])`. This is used
## by every downstream system that procedurally generates *inside* a site,
## guaranteeing that two sites with the same world_seed but different
## grid_pos produce independent terrain, AI, loot, etc.
##
## Layout: BSP-partitioned districts of a coherent biome, connected by 1-cell
## corridor doorways at shared district borders. The BSP tree itself
## provides a spanning forest of connections; extra adjacency edges open
## with low probability for BLAME!-style shortcut loops.
##
## Bump WORLDGEN_VERSION whenever the generation output changes meaning, so
## saves from old versions are detectable.

const WORLDGEN_VERSION: int = 4

const _MIN_DISTRICT_SIZE: int = 3
const _SPLIT_RATIO_MIN: float = 0.35
const _SPLIT_RATIO_MAX: float = 0.65
const _SHORTCUT_PROBABILITY: float = 0.25


static func generate(world_seed: int, size: Vector2i) -> Array[SiteData]:
	var sites: Array[SiteData] = []
	sites.resize(size.x * size.y)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "districts"])

	var districts: Array[Rect2i] = []
	_bsp_split(Rect2i(Vector2i.ZERO, size), rng, districts)

	# cell -> district index (or -1 for corridor cells, assigned later).
	var cell_district: PackedInt32Array = PackedInt32Array()
	cell_district.resize(size.x * size.y)
	for i in cell_district.size():
		cell_district[i] = -1
	for di in districts.size():
		var d: Rect2i = districts[di]
		for gy in range(d.position.y, d.position.y + d.size.y):
			for gx in range(d.position.x, d.position.x + d.size.x):
				cell_district[gy * size.x + gx] = di

	# Biome per district, plus a desirability score.
	var district_biome: PackedInt32Array = PackedInt32Array()
	district_biome.resize(districts.size())
	var district_score: PackedFloat32Array = PackedFloat32Array()
	district_score.resize(districts.size())
	for di in districts.size():
		district_biome[di] = _biome_for_district(districts[di], rng)
		district_score[di] = rng.randf()

	# Corridor cells: pick a doorway between every adjacent district pair
	# whose adjacency was selected by the BSP spanning step or by the
	# shortcut roll. Marked as -2 in cell_district so we can biome them
	# separately afterwards.
	var doorways: Array[Vector2i] = _carve_doorways(districts, size, rng)
	for cell in doorways:
		cell_district[cell.y * size.x + cell.x] = -2

	# Build SiteData.
	for gy in size.y:
		for gx in size.x:
			var site: SiteData = SiteData.new()
			site.grid_pos = Vector2i(gx, gy)
			site.site_seed = hash([world_seed, gx, gy])
			var di: int = cell_district[gy * size.x + gx]
			if di == -2:
				site.biome = SiteData.Biome.CORRIDOR
				site.score = 0.15
			else:
				site.biome = district_biome[di]
				site.score = clampf(district_score[di], 0.0, 1.0)
			sites[gy * size.x + gx] = site

	return sites


## Recursively splits `rect` along the longer axis until both halves would
## be smaller than 2 * _MIN_DISTRICT_SIZE. Appends leaves to `out`.
static func _bsp_split(rect: Rect2i, rng: RandomNumberGenerator, out: Array[Rect2i]) -> void:
	var min_split: int = _MIN_DISTRICT_SIZE * 2
	var can_x: bool = rect.size.x >= min_split
	var can_y: bool = rect.size.y >= min_split
	if not can_x and not can_y:
		out.append(rect)
		return
	var split_x: bool
	if can_x and can_y:
		split_x = rect.size.x >= rect.size.y if rng.randf() < 0.7 else rng.randi() % 2 == 0
	else:
		split_x = can_x
	var ratio: float = rng.randf_range(_SPLIT_RATIO_MIN, _SPLIT_RATIO_MAX)
	if split_x:
		var cut: int = clampi(int(rect.size.x * ratio), _MIN_DISTRICT_SIZE, rect.size.x - _MIN_DISTRICT_SIZE)
		_bsp_split(Rect2i(rect.position, Vector2i(cut, rect.size.y)), rng, out)
		_bsp_split(Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y)), rng, out)
	else:
		var cut: int = clampi(int(rect.size.y * ratio), _MIN_DISTRICT_SIZE, rect.size.y - _MIN_DISTRICT_SIZE)
		_bsp_split(Rect2i(rect.position, Vector2i(rect.size.x, cut)), rng, out)
		_bsp_split(Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut)), rng, out)


## Returns the cell coords that should be marked as corridor doorways:
##   * one cell per adjacent district pair (always — guarantees connectivity),
##   * plus optional extra openings for shortcut loops.
## A "doorway" is a single cell sitting on one side of the shared border.
static func _carve_doorways(
	districts: Array[Rect2i],
	size: Vector2i,
	rng: RandomNumberGenerator,
) -> Array[Vector2i]:
	var openings: Array[Vector2i] = []
	var seen_pairs: Dictionary = {}
	for i in districts.size():
		for j in range(i + 1, districts.size()):
			var border: Array[Vector2i] = _shared_border_cells(districts[i], districts[j])
			if border.is_empty():
				continue
			# Always-open primary connection so the world map stays one
			# connected component, plus a shortcut roll for extras.
			var key: int = i * districts.size() + j
			if seen_pairs.has(key):
				continue
			seen_pairs[key] = true
			openings.append(border[rng.randi_range(0, border.size() - 1)])
			if border.size() > 1 and rng.randf() < _SHORTCUT_PROBABILITY:
				openings.append(border[rng.randi_range(0, border.size() - 1)])
	# Clamp to bounds (defensive — BSP shouldn't produce out-of-range coords).
	var bounded: Array[Vector2i] = []
	for cell in openings:
		if cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y:
			bounded.append(cell)
	return bounded


## Returns cells inside `a` that sit directly against `b`'s border. Empty if
## the rects aren't edge-adjacent.
static func _shared_border_cells(a: Rect2i, b: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if a.position.x + a.size.x == b.position.x:                       # a left of b
		var y_lo: int = maxi(a.position.y, b.position.y)
		var y_hi: int = mini(a.position.y + a.size.y, b.position.y + b.size.y)
		for y in range(y_lo, y_hi):
			cells.append(Vector2i(a.position.x + a.size.x - 1, y))
	elif b.position.x + b.size.x == a.position.x:                     # b left of a
		var y_lo: int = maxi(a.position.y, b.position.y)
		var y_hi: int = mini(a.position.y + a.size.y, b.position.y + b.size.y)
		for y in range(y_lo, y_hi):
			cells.append(Vector2i(a.position.x, y))
	elif a.position.y + a.size.y == b.position.y:                     # a above b
		var x_lo: int = maxi(a.position.x, b.position.x)
		var x_hi: int = mini(a.position.x + a.size.x, b.position.x + b.size.x)
		for x in range(x_lo, x_hi):
			cells.append(Vector2i(x, a.position.y + a.size.y - 1))
	elif b.position.y + b.size.y == a.position.y:                     # b above a
		var x_lo: int = maxi(a.position.x, b.position.x)
		var x_hi: int = mini(a.position.x + a.size.x, b.position.x + b.size.x)
		for x in range(x_lo, x_hi):
			cells.append(Vector2i(x, a.position.y))
	return cells


## Biome correlates loosely with district shape so the overview map looks
## like a structured floor plan: long thin districts read as corridors of
## industrial machinery, near-square districts as habitats, tiny slivers
## as voids, large irregular ones as ruins.
static func _biome_for_district(d: Rect2i, rng: RandomNumberGenerator) -> int:
	var area: int = d.size.x * d.size.y
	var aspect: float = float(maxi(d.size.x, d.size.y)) / float(maxi(1, mini(d.size.x, d.size.y)))
	if area <= 6:
		return SiteData.Biome.VOID
	if aspect >= 2.2:
		return SiteData.Biome.INDUSTRIAL
	if area >= 30:
		return SiteData.Biome.RUINS
	# Default-friendly biome; small jitter so neighbouring habitats can flip
	# to RUINS occasionally and the map doesn't feel monolithic.
	return SiteData.Biome.HABITAT if rng.randf() < 0.75 else SiteData.Biome.RUINS
