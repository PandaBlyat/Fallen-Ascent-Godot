class_name DismantleJob
extends Job
##
## "Dismantle the structure at `anchor`." Worker stands adjacent and
## accumulates `progress` until DURATION seconds elapsed, then 50% of
## build ingredients drop as loose items.
##

const DURATION: float = 4.0

var anchor: Vector2i = Vector2i.ZERO
var structure_id: int = -1
var progress: float = 0.0


func _init(t: Vector2i = Vector2i.ZERO, sid: int = -1) -> void:
	kind = Kind.DISMANTLE
	anchor = t
	structure_id = sid
