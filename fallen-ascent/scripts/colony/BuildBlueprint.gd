class_name BuildBlueprint
extends RefCounted
##
## Static build definitions. Kept as code for prototype speed; later this can
## become Resource data when build UI and recipes grow.
##

enum Id {
	WALL,
	DOOR,
	LIGHT,
	EXTRACTOR,
	SENSOR,
	CHARGE_PAD,
	FABRICATOR,
	DOCK,
	REPAIR_BENCH,
	PARTS_LOOM,
	MAINTENANCE_DOCK,
	CALIBRATION_SHRINE,
}

const WALL_COLOR := Color(0.55, 0.55, 0.58, 0.55)
const DOOR_COLOR := Color(0.85, 0.55, 0.25, 0.55)
const LIGHT_COLOR := Color(1.0, 0.92, 0.35, 0.55)
const EXTRACTOR_COLOR := Color(0.45, 0.85, 0.95, 0.50)
const SENSOR_COLOR := Color(0.65, 0.95, 0.75, 0.50)
const CHARGE_PAD_COLOR := Color(0.9, 0.45, 1.0, 0.50)
const FABRICATOR_COLOR := Color(0.95, 0.72, 0.38, 0.50)
const DOCK_COLOR := Color(0.45, 0.62, 0.98, 0.50)
const REPAIR_BENCH_COLOR := Color(0.95, 0.52, 0.38, 0.50)
const PARTS_LOOM_COLOR := Color(0.58, 0.95, 0.82, 0.50)
const MAINTENANCE_DOCK_COLOR := Color(0.98, 0.82, 0.42, 0.50)
const CALIBRATION_SHRINE_COLOR := Color(0.72, 0.58, 1.0, 0.50)


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
		Id.DOCK:
			return "dock"
		Id.REPAIR_BENCH:
			return "repair bench"
		Id.PARTS_LOOM:
			return "parts loom"
		Id.MAINTENANCE_DOCK:
			return "maintenance dock"
		Id.CALIBRATION_SHRINE:
			return "calibration shrine"
		_:
			return "unknown"


static func description(id: int) -> String:
	match id:
		Id.WALL:
			return "Blocks movement and shapes rooms."
		Id.DOOR:
			return "Passable controlled barrier for future room logic."
		Id.LIGHT:
			return "Reveals nearby explored machinery."
		Id.EXTRACTOR:
			return "Pulls substrate and components from exposed systems."
		Id.SENSOR:
			return "Long-range vision mast."
		Id.CHARGE_PAD:
			return "Turns floor into recharge outlet."
		Id.FABRICATOR:
			return "Assembles circuits and power cells over time."
		Id.DOCK:
			return "Rest cradle for reducing mental tiredness."
		Id.REPAIR_BENCH:
			return "Service station where bots restore condition."
		Id.PARTS_LOOM:
			return "Consumes substrate and circuits to make advanced parts."
		Id.MAINTENANCE_DOCK:
			return "Consumes upkeep parts to keep colony machines serviced."
		Id.CALIBRATION_SHRINE:
			return "Quiet calibration point for future mental and social recovery."
		_:
			return ""


static func footprint(id: int, anchor: Vector2i, rotation: int = 0) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	match id:
		Id.EXTRACTOR:
			offsets.append(Vector2i.ZERO)
			offsets.append(Vector2i(1, 0))
			offsets.append(Vector2i(0, 1))
			offsets.append(Vector2i(1, 1))
		Id.FABRICATOR, Id.DOCK, Id.REPAIR_BENCH, Id.PARTS_LOOM, Id.CALIBRATION_SHRINE:
			offsets.append(Vector2i.ZERO)
			offsets.append(Vector2i(1, 0))
		Id.MAINTENANCE_DOCK:
			offsets.append(Vector2i.ZERO)
			offsets.append(Vector2i(1, 0))
			offsets.append(Vector2i(0, 1))
			offsets.append(Vector2i(1, 1))
		_:
			offsets.append(Vector2i.ZERO)
	var cells: Array[Vector2i] = []
	for offset in offsets:
		cells.append(anchor + _rotate_offset(offset, rotation))
	return cells


static func _rotate_offset(offset: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 4):
		1:
			return Vector2i(-offset.y, offset.x)
		2:
			return Vector2i(-offset.x, -offset.y)
		3:
			return Vector2i(offset.y, -offset.x)
		_:
			return offset


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
		Id.DOCK:
			return {Item.Kind.SCRAP: 1, Item.Kind.SUBSTRATE: 1}
		Id.REPAIR_BENCH:
			return {Item.Kind.SCRAP: 2, Item.Kind.COMPONENT: 1}
		Id.PARTS_LOOM:
			return {Item.Kind.SUBSTRATE: 2, Item.Kind.CIRCUIT: 1}
		Id.MAINTENANCE_DOCK:
			return {Item.Kind.SCRAP: 3, Item.Kind.COMPONENT: 2, Item.Kind.POWER_CELL: 1}
		Id.CALIBRATION_SHRINE:
			return {Item.Kind.CIRCUIT: 1, Item.Kind.POWER_CELL: 1}
		_:
			return {}


static func build_duration(id: int) -> float:
	match id:
		Id.EXTRACTOR:
			return 4.0
		Id.MAINTENANCE_DOCK:
			return 4.5
		Id.FABRICATOR:
			return 3.5
		Id.DOCK, Id.REPAIR_BENCH, Id.PARTS_LOOM, Id.CALIBRATION_SHRINE:
			return 3.0
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
		Id.DOCK:
			return DOCK_COLOR
		Id.REPAIR_BENCH:
			return REPAIR_BENCH_COLOR
		Id.PARTS_LOOM:
			return PARTS_LOOM_COLOR
		Id.MAINTENANCE_DOCK:
			return MAINTENANCE_DOCK_COLOR
		Id.CALIBRATION_SHRINE:
			return CALIBRATION_SHRINE_COLOR
		_:
			return WALL_COLOR


static func produces_tile(id: int) -> bool:
	return id == Id.WALL


static func production_interval(id: int) -> float:
	match id:
		Id.EXTRACTOR:
			return 8.0
		Id.FABRICATOR:
			return 12.0
		Id.PARTS_LOOM:
			return 14.0
		Id.MAINTENANCE_DOCK:
			return 24.0
		_:
			return 0.0


static func production_inputs(id: int) -> Dictionary:
	match id:
		Id.PARTS_LOOM:
			return {Item.Kind.SUBSTRATE: 1, Item.Kind.CIRCUIT: 1}
		Id.MAINTENANCE_DOCK:
			return {Item.Kind.SCRAP: 1}
		_:
			return {}


static func possible_outputs(id: int) -> Array[int]:
	match id:
		Id.EXTRACTOR:
			return [Item.Kind.COMPONENT, Item.Kind.SUBSTRATE]
		Id.FABRICATOR:
			return [Item.Kind.CIRCUIT, Item.Kind.POWER_CELL]
		Id.PARTS_LOOM:
			return [Item.Kind.COMPONENT, Item.Kind.POWER_CELL]
		_:
			return []


static func requirements(id: int) -> String:
	if id == Id.WALL:
		return "Place on floor. Becomes solid wall."
	if id == Id.CHARGE_PAD:
		return "Place on walkable explored floor. Becomes outlet."
	if requires_outlet(id):
		return "Place with at least one footprint cell on an outlet."
	return "Place on walkable explored floor, outside stockpiles."


static func requires_outlet(id: int) -> bool:
	return id == Id.EXTRACTOR \
		or id == Id.SENSOR \
		or id == Id.FABRICATOR \
		or id == Id.PARTS_LOOM \
		or id == Id.MAINTENANCE_DOCK \
		or id == Id.CALIBRATION_SHRINE


static func ingredients_text(id: int) -> String:
	var ingredients_data: Dictionary = ingredients(id)
	if ingredients_data.is_empty():
		return "none"
	var parts: Array[String] = []
	for kind in ingredients_data.keys():
		parts.append("%s x%d" % [Item.kind_name(int(kind)), int(ingredients_data[kind])])
	return ", ".join(parts)


static func production_text(id: int) -> String:
	var interval: float = production_interval(id)
	if interval <= 0.0:
		match id:
			Id.DOCK:
				return "rest: lowers mental tiredness"
			Id.REPAIR_BENCH:
				return "service: repairs bot condition"
			Id.CALIBRATION_SHRINE:
				return "calibration: future mental/social recovery"
			_:
				return "none"
	var outputs: Array[String] = []
	for kind in possible_outputs(id):
		outputs.append(Item.kind_name(kind))
	var input_text: String = ingredients_text_from(production_inputs(id))
	var prefix: String = ("Consumes %s; " % input_text) if input_text != "none" else ""
	if outputs.is_empty():
		return "%severy %.0fs: upkeep consumed" % [prefix, interval]
	return "%severy %.0fs: %s" % [prefix, interval, " / ".join(outputs)]


static func ingredients_text_from(recipe: Dictionary) -> String:
	if recipe.is_empty():
		return "none"
	var parts: Array[String] = []
	for kind in recipe.keys():
		parts.append("%s x%d" % [Item.kind_name(int(kind)), int(recipe[kind])])
	return ", ".join(parts)


static func footprint_text(id: int) -> String:
	var cells: Array[Vector2i] = footprint(id, Vector2i.ZERO)
	var max_x: int = 0
	var max_y: int = 0
	for cell in cells:
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return "%dx%d" % [max_x + 1, max_y + 1]


static func tooltip_text(id: int) -> String:
	return "%s\n%s\nCost: %s\nFootprint: %s\nBuild: %.1fs\nProduction: %s\nRequires: %s" % [
		display_name(id).capitalize(),
		description(id),
		ingredients_text(id),
		footprint_text(id),
		build_duration(id),
		production_text(id),
		requirements(id),
	]
