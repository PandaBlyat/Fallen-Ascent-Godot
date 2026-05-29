class_name RepairStructureJob
extends Job
##
## "Repair the damaged structure at `anchor`." High priority — colonists drop
## ordinary work to keep the base functional. Worker stands at the interaction
## cell and accumulates `progress` until DURATION seconds elapse, then
## StructureManager.repair_structure_at restores the structure to full condition.
##

const DURATION: float = 5.0

var anchor: Vector2i = Vector2i.ZERO
var structure_id: int = -1
var progress: float = 0.0


func _init(t: Vector2i = Vector2i.ZERO, sid: int = -1) -> void:
	kind = Kind.REPAIR_STRUCTURE
	anchor = t
	structure_id = sid
