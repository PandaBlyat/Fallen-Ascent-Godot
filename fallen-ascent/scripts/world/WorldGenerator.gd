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
## Bump WORLDGEN_VERSION whenever the generation output changes meaning, so
## saves from old versions are detectable.

const WORLDGEN_VERSION: int = 1


static func generate(world_seed: int, size: Vector2i) -> Array[SiteData]:
	var sites: Array[SiteData] = []
	sites.resize(size.x * size.y)

	# Two noise layers: one for biome selection, one for desirability score.
	var biome_noise: FastNoiseLite = FastNoiseLite.new()
	biome_noise.seed = world_seed
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_noise.frequency = 0.08

	var score_noise: FastNoiseLite = FastNoiseLite.new()
	score_noise.seed = world_seed ^ 0x5A5A5A5A
	score_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	score_noise.frequency = 0.15

	for gy in size.y:
		for gx in size.x:
			var site: SiteData = SiteData.new()
			site.grid_pos = Vector2i(gx, gy)
			site.site_seed = hash([world_seed, gx, gy])

			var b_sample: float = biome_noise.get_noise_2d(gx, gy)  # ~[-1, 1]
			site.biome = _biome_from_sample(b_sample)

			var s_sample: float = score_noise.get_noise_2d(gx, gy)
			site.score = clampf((s_sample + 1.0) * 0.5, 0.0, 1.0)

			sites[gy * size.x + gx] = site

	return sites


static func _biome_from_sample(s: float) -> int:
	# Buckets are tuned so HABITAT (the friendliest placeholder) shows up most.
	if s < -0.45:
		return SiteData.Biome.VOID
	if s < 0.10:
		return SiteData.Biome.HABITAT
	if s < 0.55:
		return SiteData.Biome.INDUSTRIAL
	return SiteData.Biome.RUINS
