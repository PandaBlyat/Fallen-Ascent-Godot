class_name BuildBlueprint
extends RefCounted
##
## Static build definitions. Kept as code for prototype speed; later this can
## become Resource data when build UI and recipes grow.
##

enum Id { WALL, DOOR, LIGHT, EXTRACTOR, SENSOR, CHARGE_PAD, FABRICATOR }

const WALL_COLOR := Color(0.55, 0.55, 0.58, 0.55)
const DOOR_COLOR := Color(0.85, 0.55, 0.25, 0.55)
const LIGHT_COLOR := Color(1.0, 0.92, 0.35, 0.55)
const EXTRACTOR_COLOR := Color(0.45, 0.85, 0.95, 0.50)
const SENSOR_COLOR := Color(0.65, 0.95, 0.75, 0.50)
const CHARGE_PAD_COLOR := Color(0.9, 0.45, 1.0, 0.50)
const FABRICATOR_COLOR := Color(0.95, 0.72, 0.38, 0.50)


static func display_name(id: int) -> String:
	match id:
		Id.WALL:
			return "wall"
		Id.DOOR:
			return "door"
		Id.LIGHT:
			return "light"
		Id.EXTRACTOR:
			return "extractor"
		Id.SENSOR:
			return "sensor"
		Id.CHARGE_PAD:
			return "charge pad"
		Id.FABRICATOR:
			return "fabricator"
		_:
			return "unknown"


static func footprint(id: int, anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	match id:
		Id.EXTRACTOR:
			cells.append(anchor)
			cells.append(anchor + Vector2i(1, 0))
			cells.append(anchor + Vector2i(0, 1))
			cells.append(anchor + Vector2i(1, 1))
		Id.FABRICATOR:
			cells.append(anchor)
			cells.append(anchor + Vector2i(1, 0))
		_:
			cells.append(anchor)
	return cells


static func ingredients(id: int) -> Dictionary:
	match id:
		Id.WALL:
			return {Item.Kind.SCRAP: 1}
		Id.DOOR:
			return {Item.Kind.SCRAP: 1, Item.Kind.COMPONENT: 1}
		Id.LIGHT:
			return {Item.Kind.COMPONENT: 1}
		Id.EXTRACTOR:
			return {Item.Kind.SCRAP: 2, Item.Kind.SUBSTRATE: 2, Item.Kind.COMPONENT: 1}
		Id.SENSOR:
			return {Item.Kind.COMPONENT: 1, Item.Kind.CIRCUIT: 1}
		Id.CHARGE_PAD:
			return {Item.Kind.SCRAP: 1, Item.Kind.COMPONENT: 1, Item.Kind.POWER_CELL: 1}
		Id.FABRICATOR:
			return {Item.Kind.SCRAP: 2, Item.Kind.SUBSTRATE: 1, Item.Kind.CIRCUIT: 1}
		_:
			return {}


static func build_duration(id: int) -> float:
	match id:
		Id.EXTRACTOR:
			return 4.0
		Id.FABRICATOR:
			return 3.5
		Id.DOOR, Id.LIGHT:
			return 2.5
		_:
			return 2.0


static func ghost_color(id: int) -> Color:
	match id:
		Id.DOOR:
			return DOOR_COLOR
		Id.LIGHT:
			return LIGHT_COLOR
		Id.EXTRACTOR:
			return EXTRACTOR_COLOR
		Id.SENSOR:
			return SENSOR_COLOR
		Id.CHARGE_PAD:
			return CHARGE_PAD_COLOR
		Id.FABRICATOR:
			return FABRICATOR_COLOR
		_:
			return WALL_COLOR


static func produces_tile(id: int) -> bool:
	return id == Id.WALL
