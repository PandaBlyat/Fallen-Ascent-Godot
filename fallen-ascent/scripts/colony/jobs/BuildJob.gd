class_name BuildJob
extends Job
##
## "Place a wall on `target`." Worker first picks up a `material_kind` item
## (the StockpileManager pairs the job with a free source Item when posted,
## so the worker can find it). After delivering it adjacent to the target,
## the worker spends BUILD_DURATION seconds and sets the tile to TILE_WALL.
##

const BUILD_DURATION: float = 2.0

var target: Vector2i = Vector2i.ZERO
var material_kind: int = Item.Kind.SCRAP
var source_item: Node = null              ## Item being consumed; assigned at claim time
var progress: float = 0.0


func _init(t: Vector2i = Vector2i.ZERO, mk: int = Item.Kind.SCRAP) -> void:
	kind = Kind.BUILD
	target = t
	material_kind = mk
