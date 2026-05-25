class_name BuildBlueprint
extends RefCounted
##
## Static build definitions. Kept as code for prototype speed; later this can
## become Resource data when build UI and recipes grow.
##
## Enum names are kept stable across the resource rename (PARTS_LOOM still
## reads "assembly press", MAINTENANCE_DOCK still reads "mechanic dock") so
## scenes and saved data references stay valid.
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
	MEDITATION_PAD,
	SENTIENCE_CRADLE,
	FABRICATION_SPOT,
	STORAGE_BIN,
	OUTLET_EXTENSION,
	RUDIMENTARY_SENSOR,
	SMALL_LIGHT_DEVICE,
	LARGE_LIGHT_DEVICE,
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
const MEDITATION_PAD_COLOR := Color(0.62, 0.78, 1.0, 0.50)
const SENTIENCE_CRADLE_COLOR := Color(0.95, 0.88, 0.55, 0.55)
const FABRICATION_SPOT_COLOR := Color(0.90, 0.68, 0.42, 0.55)
const STORAGE_BIN_COLOR := Color(0.68, 0.52, 0.32, 0.55)
const OUTLET_EXTENSION_COLOR := Color(0.35, 0.95, 1.0, 0.55)
const RUDIMENTARY_SENSOR_COLOR := Color(0.55, 0.95, 0.62, 0.55)
const SMALL_LIGHT_DEVICE_COLOR := Color(1.0, 0.85, 0.35, 0.55)
const LARGE_LIGHT_DEVICE_COLOR := Color(1.0, 0.66, 0.26, 0.55)


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
			return "assembly press"
		Id.MAINTENANCE_DOCK:
			return "mechanic dock"
		Id.CALIBRATION_SHRINE:
			return "calibration shrine"
		Id.MEDITATION_PAD:
			return "meditation pad"
		Id.SENTIENCE_CRADLE:
			return "sentience cradle"
		Id.FABRICATION_SPOT:
			return "fabrication spot"
		Id.STORAGE_BIN:
			return "storage bin"
		Id.OUTLET_EXTENSION:
			return "outlet extension"
		Id.RUDIMENTARY_SENSOR:
			return "rudimentary sensor"
		Id.SMALL_LIGHT_DEVICE:
			return "small light device"
		Id.LARGE_LIGHT_DEVICE:
			return "large light device"
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
			return "Worker-operated machine that pulls plating and mechanism scrap from exposed systems."
		Id.SENSOR:
			return "Long-range vision mast."
		Id.CHARGE_PAD:
			return "Turns floor into recharge outlet."
		Id.FABRICATOR:
			return "Worker-operated machine that assembles datacores and charge cells."
		Id.DOCK:
			return "Rest cradle for reducing mental exhaustion."
		Id.REPAIR_BENCH:
			return "Service station where bots restore condition."
		Id.PARTS_LOOM:
			return "Worker-operated machine that consumes plating and datacores to make advanced parts."
		Id.MAINTENANCE_DOCK:
			return "Required structure inside a Mechanic Room. Gates limb-heal services for room occupants."
		Id.CALIBRATION_SHRINE:
			return "Quiet calibration point for future mental and social recovery."
		Id.MEDITATION_PAD:
			return "A still spot where bots gather wisdom over time. Place inside a Meditation Chamber for the room bonus."
		Id.SENTIENCE_CRADLE:
			return "Worker-operated machine that forges a new worker over a long cycle. Hungry for refined parts."
		Id.FABRICATION_SPOT:
			return "Tiny work marker where workers craft placeable objects from stored parts."
		Id.STORAGE_BIN:
			return "Place on a stockpile tile to raise that tile's item capacity to 12."
		Id.OUTLET_EXTENSION:
			return "Place on an outlet so up to two workers can recharge there."
		Id.RUDIMENTARY_SENSOR:
			return "Short-radius crafted sensor."
		Id.SMALL_LIGHT_DEVICE:
			return "Small crafted work light."
		Id.LARGE_LIGHT_DEVICE:
			return "Large crafted work light with wider coverage."
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
		Id.FABRICATOR, Id.DOCK, Id.REPAIR_BENCH, Id.PARTS_LOOM, Id.CALIBRATION_SHRINE, Id.MEDITATION_PAD:
			offsets.append(Vector2i.ZERO)
			offsets.append(Vector2i(1, 0))
		Id.MAINTENANCE_DOCK, Id.SENTIENCE_CRADLE:
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
			return {Item.Kind.SCRAP: 1, Item.Kind.MECHANISM: 1}
		Id.LIGHT:
			return {Item.Kind.MECHANISM: 1}
		Id.EXTRACTOR:
			return {Item.Kind.SCRAP: 2, Item.Kind.PLATING: 2, Item.Kind.MECHANISM: 1}
		Id.SENSOR:
			return {Item.Kind.MECHANISM: 1, Item.Kind.DATACORE: 1}
		Id.CHARGE_PAD:
			return {Item.Kind.SCRAP: 1, Item.Kind.MECHANISM: 1, Item.Kind.CHARGE_CELL: 1}
		Id.FABRICATOR:
			return {Item.Kind.SCRAP: 2, Item.Kind.PLATING: 1, Item.Kind.DATACORE: 1}
		Id.DOCK:
			return {Item.Kind.SCRAP: 1, Item.Kind.PLATING: 1}
		Id.REPAIR_BENCH:
			return {Item.Kind.SCRAP: 2, Item.Kind.MECHANISM: 1}
		Id.PARTS_LOOM:
			return {Item.Kind.PLATING: 2, Item.Kind.DATACORE: 1}
		Id.MAINTENANCE_DOCK:
			return {Item.Kind.SCRAP: 3, Item.Kind.MECHANISM: 2, Item.Kind.CHARGE_CELL: 1}
		Id.CALIBRATION_SHRINE:
			return {Item.Kind.DATACORE: 1, Item.Kind.CHARGE_CELL: 1}
		Id.MEDITATION_PAD:
			return {Item.Kind.SCRAP: 2, Item.Kind.PLATING: 1}
		Id.SENTIENCE_CRADLE:
			return {Item.Kind.SCRAP: 8, Item.Kind.PLATING: 6, Item.Kind.MECHANISM: 4, Item.Kind.DATACORE: 2}
		Id.FABRICATION_SPOT:
			return {Item.Kind.SCRAP: 1, Item.Kind.PLATING: 1}
		Id.STORAGE_BIN:
			return {Item.Kind.STORAGE_BIN: 1}
		Id.OUTLET_EXTENSION:
			return {Item.Kind.OUTLET_EXTENSION: 1}
		Id.RUDIMENTARY_SENSOR:
			return {Item.Kind.RUDIMENTARY_SENSOR: 1}
		Id.SMALL_LIGHT_DEVICE:
			return {Item.Kind.SMALL_LIGHT_DEVICE: 1}
		Id.LARGE_LIGHT_DEVICE:
			return {Item.Kind.LARGE_LIGHT_DEVICE: 1}
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
		Id.DOCK, Id.REPAIR_BENCH, Id.PARTS_LOOM, Id.CALIBRATION_SHRINE, Id.MEDITATION_PAD:
			return 3.0
		Id.SENTIENCE_CRADLE:
			return 8.0
		Id.FABRICATION_SPOT:
			return 1.5
		Id.STORAGE_BIN, Id.OUTLET_EXTENSION, Id.RUDIMENTARY_SENSOR, Id.SMALL_LIGHT_DEVICE, Id.LARGE_LIGHT_DEVICE:
			return 0.8
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
		Id.MEDITATION_PAD:
			return MEDITATION_PAD_COLOR
		Id.SENTIENCE_CRADLE:
			return SENTIENCE_CRADLE_COLOR
		Id.FABRICATION_SPOT:
			return FABRICATION_SPOT_COLOR
		Id.STORAGE_BIN:
			return STORAGE_BIN_COLOR
		Id.OUTLET_EXTENSION:
			return OUTLET_EXTENSION_COLOR
		Id.RUDIMENTARY_SENSOR:
			return RUDIMENTARY_SENSOR_COLOR
		Id.SMALL_LIGHT_DEVICE:
			return SMALL_LIGHT_DEVICE_COLOR
		Id.LARGE_LIGHT_DEVICE:
			return LARGE_LIGHT_DEVICE_COLOR
		_:
			return WALL_COLOR


static func produces_tile(id: int) -> bool:
	return id == Id.WALL


static func production_interval(id: int) -> float:
	match id:
		Id.EXTRACTOR:
			return 7.0
		Id.FABRICATOR:
			return 9.0
		Id.PARTS_LOOM:
			return 10.0
		Id.SENTIENCE_CRADLE:
			return 120.0
		_:
			return 0.0


static func production_inputs(id: int) -> Dictionary:
	match id:
		Id.PARTS_LOOM:
			return {Item.Kind.PLATING: 1, Item.Kind.DATACORE: 1}
		Id.SENTIENCE_CRADLE:
			return {
				Item.Kind.SCRAP: 20,
				Item.Kind.PLATING: 10,
				Item.Kind.MECHANISM: 8,
				Item.Kind.DATACORE: 4,
				Item.Kind.CHARGE_CELL: 2,
			}
		_:
			return {}


static func possible_outputs(id: int) -> Array[int]:
	match id:
		Id.EXTRACTOR:
			return [Item.Kind.MECHANISM, Item.Kind.PLATING]
		Id.FABRICATOR:
			return [Item.Kind.DATACORE, Item.Kind.CHARGE_CELL]
		Id.PARTS_LOOM:
			return [Item.Kind.MECHANISM, Item.Kind.CHARGE_CELL]
		_:
			return []


static func requirements(id: int) -> String:
	if id == Id.WALL:
		return "Place on floor. Becomes solid wall."
	if id == Id.CHARGE_PAD:
		return "Place on walkable explored floor. Becomes outlet."
	if id == Id.STORAGE_BIN:
		return "Place on a stockpile tile after crafting one at a fabrication spot."
	if id == Id.OUTLET_EXTENSION:
		return "Place on an outlet tile after crafting one at a fabrication spot."
	if is_object_placement(id):
		return "Place on walkable explored floor after crafting one at a fabrication spot."
	if is_worker_operated(id):
		var outlet_text: String = ""
		if outlet_range(id) > 0:
			outlet_text = " and within %d tiles of an outlet" % outlet_range(id)
		if requires_outlet(id):
			outlet_text = " and with at least one footprint cell on an outlet"
		return "Place in a Machine Room%s." % outlet_text
	if outlet_range(id) > 0:
		return "Place within %d tiles of an outlet." % outlet_range(id)
	if requires_outlet(id):
		return "Place with at least one footprint cell on an outlet."
	return "Place on walkable explored floor, outside stockpiles."


static func requires_outlet(id: int) -> bool:
	return id == Id.EXTRACTOR \
		or id == Id.SENSOR \
		or id == Id.FABRICATOR \
		or id == Id.PARTS_LOOM \
		or id == Id.MAINTENANCE_DOCK \
		or id == Id.CALIBRATION_SHRINE \
		or id == Id.SENTIENCE_CRADLE


static func is_worker_operated(id: int) -> bool:
	return id == Id.EXTRACTOR \
		or id == Id.FABRICATOR \
		or id == Id.PARTS_LOOM \
		or id == Id.SENTIENCE_CRADLE


static func outlet_range(id: int) -> int:
	if id == Id.LIGHT:
		return 15
	return -1


static func is_object_placement(id: int) -> bool:
	return id == Id.STORAGE_BIN \
		or id == Id.OUTLET_EXTENSION \
		or id == Id.RUDIMENTARY_SENSOR \
		or id == Id.SMALL_LIGHT_DEVICE \
		or id == Id.LARGE_LIGHT_DEVICE


static func object_item_kind(id: int) -> int:
	match id:
		Id.STORAGE_BIN:
			return Item.Kind.STORAGE_BIN
		Id.OUTLET_EXTENSION:
			return Item.Kind.OUTLET_EXTENSION
		Id.RUDIMENTARY_SENSOR:
			return Item.Kind.RUDIMENTARY_SENSOR
		Id.SMALL_LIGHT_DEVICE:
			return Item.Kind.SMALL_LIGHT_DEVICE
		Id.LARGE_LIGHT_DEVICE:
			return Item.Kind.LARGE_LIGHT_DEVICE
		_:
			return -1


static func object_blueprint_for_item(kind: int) -> int:
	match kind:
		Item.Kind.STORAGE_BIN:
			return Id.STORAGE_BIN
		Item.Kind.OUTLET_EXTENSION:
			return Id.OUTLET_EXTENSION
		Item.Kind.RUDIMENTARY_SENSOR:
			return Id.RUDIMENTARY_SENSOR
		Item.Kind.SMALL_LIGHT_DEVICE:
			return Id.SMALL_LIGHT_DEVICE
		Item.Kind.LARGE_LIGHT_DEVICE:
			return Id.LARGE_LIGHT_DEVICE
		_:
			return -1


static func crafted_object_blueprints() -> Array[int]:
	return [
		Id.STORAGE_BIN,
		Id.OUTLET_EXTENSION,
		Id.RUDIMENTARY_SENSOR,
		Id.SMALL_LIGHT_DEVICE,
		Id.LARGE_LIGHT_DEVICE,
	]


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
				return "rest: lowers mental exhaustion"
			Id.REPAIR_BENCH:
				return "service: repairs bot condition"
			Id.CALIBRATION_SHRINE:
				return "calibration: future mental/social recovery"
			Id.MEDITATION_PAD:
				return "meditation: bots earn wisdom while sitting"
			_:
				return "none"
	if id == Id.SENTIENCE_CRADLE:
		var inputs_text: String = ingredients_text_from(production_inputs(id))
		return "Worker job consumes %s; %.0fs work: new worker" % [inputs_text, interval]
	var outputs: Array[String] = []
	for kind in possible_outputs(id):
		outputs.append(Item.kind_name(kind))
	var input_text: String = ingredients_text_from(production_inputs(id))
	var prefix: String = ("Consumes %s; " % input_text) if input_text != "none" else ""
	if outputs.is_empty():
		return "%s%.0fs worker job" % [prefix, interval]
	return "%s%.0fs worker job: %s" % [prefix, interval, " / ".join(outputs)]


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
