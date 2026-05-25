class_name Item
extends Node2D
##
## A loose or stored stack on the floor. Drawn as a small filled square,
## with the stack count overlaid when >1.
## Lifecycle:
##   1. Spawned on a grid cell by ColonySite._spawn_item after a mine.
##   2. Reserved by a HaulJob (reserved_by = worker).
##   3. Picked up: reparented to the worker, kept hidden during carry.
##   4. Dropped: reparented to the StockpileZone, visible again, occupant
##      slot recorded on the zone. Same-kind stacks merge up to MAX_STACK.
##
## Tier story (read left→right: raw → structural → mechanical → digital → energy):
##   SCRAP, PLATING, MECHANISM, DATACORE, CHARGE_CELL.
## Wisdom is intentionally NOT here — it is an abstract counter on TechManager.
##

enum Kind {
	SCRAP,
	MECHANISM,
	PLATING,
	DATACORE,
	CHARGE_CELL,
	STORAGE_BIN,
	OUTLET_EXTENSION,
	RUDIMENTARY_SENSOR,
	SMALL_LIGHT_DEVICE,
	LARGE_LIGHT_DEVICE,
}

enum Category {
	RAW,
	STRUCTURAL,
	MECHANICAL,
	DIGITAL,
	ENERGY,
}

const SCRAP_COLOR := Color(0.85, 0.75, 0.25)
const MECHANISM_COLOR := Color(0.55, 0.75, 0.95)
const PLATING_COLOR := Color(0.7, 0.95, 0.55)
const DATACORE_COLOR := Color(0.45, 1.0, 0.82)
const CHARGE_CELL_COLOR := Color(0.95, 0.45, 1.0)
const STORAGE_BIN_COLOR := Color(0.68, 0.52, 0.32)
const OUTLET_EXTENSION_COLOR := Color(0.35, 0.95, 1.0)
const RUDIMENTARY_SENSOR_COLOR := Color(0.55, 0.95, 0.62)
const SMALL_LIGHT_DEVICE_COLOR := Color(1.0, 0.85, 0.35)
const LARGE_LIGHT_DEVICE_COLOR := Color(1.0, 0.66, 0.26)
const SIZE_PX: float = 8.0
const STACK_FONT_SIZE: int = 10
const STACK_OUTLINE_SIZE: int = 2
const MAX_STACK: int = 16
const ITEM_ATLAS_PATH := "res://resources/items/placeholder_items_atlas.png"
const OBJECT_ATLAS_PATH := "res://resources/objects/craftable_objects_atlas.png"
const STACK_FONT: Font = preload("res://resources/Orbitron-VariableFont_wght.ttf")
const ITEM_REGION_SIZE := Vector2(32, 32)

var kind: int = Kind.SCRAP
var grid: Vector2i = Vector2i.ZERO
var count: int = 1
var reserved_by: Node = null
var _atlas: Texture2D = null
var _object_atlas: Texture2D = null


func _ready() -> void:
	_atlas = load(ITEM_ATLAS_PATH) as Texture2D
	_object_atlas = load(OBJECT_ATLAS_PATH) as Texture2D
	queue_redraw()


func setup(g: Vector2i, k: int = Kind.SCRAP, c: int = 1) -> void:
	grid = g
	kind = k
	count = c
	position = Chunk.grid_to_pixel_center(g)
	queue_redraw()


func set_grid(g: Vector2i) -> void:
	grid = g
	position = Chunk.grid_to_pixel_center(g)


func get_grid() -> Vector2i:
	return grid


func add_to_stack(amount: int, max_stack: int = MAX_STACK) -> int:
	## Adds `amount` to this stack up to `max_stack`, returns the overflow.
	var room: int = max_stack - count
	var taken: int = min(amount, room)
	count += taken
	queue_redraw()
	return amount - taken


func color() -> Color:
	match kind:
		Kind.MECHANISM: return MECHANISM_COLOR
		Kind.PLATING: return PLATING_COLOR
		Kind.DATACORE: return DATACORE_COLOR
		Kind.CHARGE_CELL: return CHARGE_CELL_COLOR
		Kind.STORAGE_BIN: return STORAGE_BIN_COLOR
		Kind.OUTLET_EXTENSION: return OUTLET_EXTENSION_COLOR
		Kind.RUDIMENTARY_SENSOR: return RUDIMENTARY_SENSOR_COLOR
		Kind.SMALL_LIGHT_DEVICE: return SMALL_LIGHT_DEVICE_COLOR
		Kind.LARGE_LIGHT_DEVICE: return LARGE_LIGHT_DEVICE_COLOR
		_: return SCRAP_COLOR


static func kind_color(k: int) -> Color:
	match k:
		Kind.MECHANISM: return MECHANISM_COLOR
		Kind.PLATING: return PLATING_COLOR
		Kind.DATACORE: return DATACORE_COLOR
		Kind.CHARGE_CELL: return CHARGE_CELL_COLOR
		Kind.STORAGE_BIN: return STORAGE_BIN_COLOR
		Kind.OUTLET_EXTENSION: return OUTLET_EXTENSION_COLOR
		Kind.RUDIMENTARY_SENSOR: return RUDIMENTARY_SENSOR_COLOR
		Kind.SMALL_LIGHT_DEVICE: return SMALL_LIGHT_DEVICE_COLOR
		Kind.LARGE_LIGHT_DEVICE: return LARGE_LIGHT_DEVICE_COLOR
		_: return SCRAP_COLOR


static func kind_name(k: int) -> String:
	match k:
		Kind.MECHANISM:
			return "mechanism"
		Kind.PLATING:
			return "plating"
		Kind.DATACORE:
			return "datacore"
		Kind.CHARGE_CELL:
			return "charge cell"
		Kind.STORAGE_BIN:
			return "storage bin"
		Kind.OUTLET_EXTENSION:
			return "outlet extension"
		Kind.RUDIMENTARY_SENSOR:
			return "rudimentary sensor"
		Kind.SMALL_LIGHT_DEVICE:
			return "small light device"
		Kind.LARGE_LIGHT_DEVICE:
			return "large light device"
		_:
			return "scrap"


static func kind_category(k: int) -> int:
	match k:
		Kind.SCRAP:
			return Category.RAW
		Kind.PLATING, Kind.STORAGE_BIN:
			return Category.STRUCTURAL
		Kind.MECHANISM, Kind.OUTLET_EXTENSION:
			return Category.MECHANICAL
		Kind.DATACORE, Kind.RUDIMENTARY_SENSOR:
			return Category.DIGITAL
		Kind.CHARGE_CELL, Kind.SMALL_LIGHT_DEVICE, Kind.LARGE_LIGHT_DEVICE:
			return Category.ENERGY
		_:
			return Category.RAW


static func category_name(category: int) -> String:
	match category:
		Category.STRUCTURAL:
			return "structural"
		Category.MECHANICAL:
			return "mechanical"
		Category.DIGITAL:
			return "digital"
		Category.ENERGY:
			return "energy"
		_:
			return "raw"


static func category_color(category: int) -> Color:
	match category:
		Category.STRUCTURAL:
			return PLATING_COLOR
		Category.MECHANICAL:
			return MECHANISM_COLOR
		Category.DIGITAL:
			return DATACORE_COLOR
		Category.ENERGY:
			return CHARGE_CELL_COLOR
		_:
			return SCRAP_COLOR


static func kind_description(k: int) -> String:
	match k:
		Kind.MECHANISM:
			return "moving-part assembly: actuators, joints, frame links"
		Kind.PLATING:
			return "refined structural sheet"
		Kind.DATACORE:
			return "logic / data substrate for sensors and machine cognition"
		Kind.CHARGE_CELL:
			return "portable stored power"
		Kind.STORAGE_BIN:
			return "crafted storage object: raises one stockpile tile capacity to 12"
		Kind.OUTLET_EXTENSION:
			return "crafted outlet object: lets two workers recharge from one outlet"
		Kind.RUDIMENTARY_SENSOR:
			return "crafted vision object: short-radius reveal source"
		Kind.SMALL_LIGHT_DEVICE:
			return "crafted light object: small work light"
		Kind.LARGE_LIGHT_DEVICE:
			return "crafted light object: large work light"
		_:
			return "loose salvaged metal"


static func acquisition_text(k: int) -> String:
	match k:
		Kind.SCRAP:
			return "Mine walls, scrape rust, or salvage loose machinery."
		Kind.PLATING:
			return "Mine walls/service cores/rich walls, salvage machinery, or run an extractor."
		Kind.MECHANISM:
			return "Mine service cores/rich walls, salvage machinery, run extractor, or craft through assembly press."
		Kind.DATACORE:
			return "Mine service cores/rich walls, salvage electronics, or run a fabricator."
		Kind.CHARGE_CELL:
			return "Mine service cores, salvage batteries, run fabricator, or craft through assembly press."
		Kind.STORAGE_BIN, Kind.OUTLET_EXTENSION, Kind.RUDIMENTARY_SENSOR, Kind.SMALL_LIGHT_DEVICE, Kind.LARGE_LIGHT_DEVICE:
			return "Add crafting order at fabrication spot, then place from Objects tab."
		_:
			return "Acquire through mining, salvage, or production jobs."


static func craftable_object_kinds() -> Array[int]:
	return [
		Kind.STORAGE_BIN,
		Kind.OUTLET_EXTENSION,
		Kind.RUDIMENTARY_SENSOR,
		Kind.SMALL_LIGHT_DEVICE,
		Kind.LARGE_LIGHT_DEVICE,
	]


static func is_craftable_object_kind(k: int) -> bool:
	return craftable_object_kinds().has(k)


static func object_atlas_index(k: int) -> int:
	match k:
		Kind.STORAGE_BIN:
			return 0
		Kind.OUTLET_EXTENSION:
			return 1
		Kind.RUDIMENTARY_SENSOR:
			return 2
		Kind.SMALL_LIGHT_DEVICE:
			return 3
		Kind.LARGE_LIGHT_DEVICE:
			return 4
		_:
			return -1


static func craft_recipe(k: int) -> Dictionary:
	match k:
		Kind.STORAGE_BIN:
			return {Kind.SCRAP: 2, Kind.PLATING: 1}
		Kind.OUTLET_EXTENSION:
			return {Kind.MECHANISM: 1, Kind.CHARGE_CELL: 1}
		Kind.RUDIMENTARY_SENSOR:
			return {Kind.MECHANISM: 1, Kind.DATACORE: 1}
		Kind.SMALL_LIGHT_DEVICE:
			return {Kind.SCRAP: 1, Kind.MECHANISM: 1}
		Kind.LARGE_LIGHT_DEVICE:
			return {Kind.PLATING: 2, Kind.MECHANISM: 1, Kind.CHARGE_CELL: 1}
		_:
			return {}


static func craft_duration(k: int) -> float:
	match k:
		Kind.STORAGE_BIN:
			return 5.0
		Kind.OUTLET_EXTENSION:
			return 6.0
		Kind.RUDIMENTARY_SENSOR:
			return 7.0
		Kind.SMALL_LIGHT_DEVICE:
			return 4.0
		Kind.LARGE_LIGHT_DEVICE:
			return 8.0
		_:
			return 0.0


static func recipe_text(recipe: Dictionary) -> String:
	if recipe.is_empty():
		return "none"
	var parts: Array[String] = []
	for recipe_kind in recipe.keys():
		parts.append("%s x%d" % [kind_name(int(recipe_kind)), int(recipe[recipe_kind])])
	return ", ".join(parts)


static func stack_label(k: int, amount: int) -> String:
	return "%s x%d" % [kind_name(k), amount]


func _draw() -> void:
	var r := Rect2(-Vector2(SIZE_PX, SIZE_PX) * 0.5, Vector2(SIZE_PX, SIZE_PX))
	if is_craftable_object_kind(kind) and _object_atlas != null:
		var object_source := Rect2(Vector2(object_atlas_index(kind) * int(ITEM_REGION_SIZE.x), 0), ITEM_REGION_SIZE)
		draw_texture_rect_region(_object_atlas, Rect2(-ITEM_REGION_SIZE * 0.5, ITEM_REGION_SIZE), object_source)
	elif _atlas != null:
		var source := Rect2(Vector2(kind * int(ITEM_REGION_SIZE.x), 0), ITEM_REGION_SIZE)
		draw_texture_rect_region(_atlas, Rect2(-ITEM_REGION_SIZE * 0.5, ITEM_REGION_SIZE), source)
	else:
		draw_rect(r, color())
	if count > 1:
		var font: Font = STACK_FONT
		var label: String = str(count)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, STACK_FONT_SIZE)
		var pos := Vector2(-text_size.x * 0.5, text_size.y * 0.32)
		draw_string_outline(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, STACK_FONT_SIZE, STACK_OUTLINE_SIZE, Color.BLACK)
		draw_string(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, STACK_FONT_SIZE, Color.WHITE)
