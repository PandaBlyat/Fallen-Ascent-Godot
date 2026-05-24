class_name ScrapeRustJob
extends Job
##
## Low-priority maintenance job. Worker stands on rust tile and scrapes it
## back to floor.
##

const DURATION: float = 1.4

var target: Vector2i = Vector2i.ZERO
var progress: float = 0.0


func _init(t: Vector2i = Vector2i.ZERO) -> void:
	kind = Kind.SCRAPE_RUST
	target = t
