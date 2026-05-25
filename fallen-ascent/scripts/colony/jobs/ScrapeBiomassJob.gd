class_name ScrapeBiomassJob
extends Job
##
## Low-priority maintenance job. Worker clears grass biomass overlay and may
## produce a biomass item.
##

const DURATION: float = 0.9

var target: Vector2i = Vector2i.ZERO
var progress: float = 0.0


func _init(t: Vector2i = Vector2i.ZERO) -> void:
	kind = Kind.SCRAPE_BIOMASS
	target = t
