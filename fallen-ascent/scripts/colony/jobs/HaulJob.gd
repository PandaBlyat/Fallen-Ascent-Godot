class_name HaulJob
extends Job
##
## "Pick up `item` and place it on `dropoff`." Dropoff cell is reserved
## (occupant slot held empty for this item) when the job is created.
##

var item: Node = null              ## Item node, on the ground
var dropoff_zone: Node = null      ## StockpileZone owning the reserved cell
var dropoff: Vector2i = Vector2i.ZERO


func _init(it: Node = null, zone: Node = null, cell: Vector2i = Vector2i.ZERO) -> void:
	kind = Kind.HAUL
	item = it
	dropoff_zone = zone
	dropoff = cell
