class_name SiteData
extends Resource
##
## Per-cell data on the world overview map. Also serves as the handoff payload
## when the player picks a site and the Colony scene loads.
##

enum Biome {
	VOID,       ## dead, mostly empty space
	HABITAT,    ## once-inhabited interior; placeholder-friendly biome
	INDUSTRIAL, ## machinery, denser structures
	RUINS,      ## collapsed / debris-heavy
}

@export var grid_pos: Vector2i = Vector2i.ZERO
## Deterministic per-site seed, derived from (world_seed, grid_pos).
## Use this to seed every system that procedurally generates inside the site.
@export var site_seed: int = 0
@export var biome: int = Biome.HABITAT
## Aggregate desirability score in [0, 1] — used for tooltips, AI hints, etc.
@export var score: float = 0.0


static func biome_color(b: int) -> Color:
	match b:
		Biome.VOID:       return Color(0.05, 0.05, 0.08)
		Biome.HABITAT:    return Color(0.35, 0.55, 0.60)
		Biome.INDUSTRIAL: return Color(0.60, 0.45, 0.30)
		Biome.RUINS:      return Color(0.40, 0.35, 0.40)
	return Color.MAGENTA


static func biome_name(b: int) -> String:
	match b:
		Biome.VOID:       return "Void"
		Biome.HABITAT:    return "Habitat"
		Biome.INDUSTRIAL: return "Industrial"
		Biome.RUINS:      return "Ruins"
	return "?"
