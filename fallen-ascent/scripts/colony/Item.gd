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

enum Kind { SCRAP, MECHANISM, PLATING, DATACORE, CHARGE_CELL }

const SCRAP_COLOR := Color(0.85, 0.75, 0.25)
const MECHANISM_COLOR := Color(0.55, 0.75, 0.95)
const PLATING_COLOR := Color(0.7, 0.95, 0.55)
const DATACORE_COLOR := Color(0.45, 1.0, 0.82)
const CHARGE_CELL_COLOR := Color(0.95, 0.45, 1.0)
const SIZE_PX: float = 8.0
const STACK_FONT_SIZE: int = 10
const STACK_OUTLINE_SIZE: int = 2
const MAX_STACK: int = 16
const ITEM_ATLAS_PATH := "res://resources/items/placeholder_items_atlas.png"
const ITEM_REGION_SIZE := Vector2(16, 16)

var kind: int = Kind.SCRAP
var grid: Vector2i = Vector2i.ZERO
var count: int = 1
var reserved_by: Node = null
var _atlas: Texture2D = null


func _ready() -> void:
	_atlas = load(ITEM_ATLAS_PATH) as Texture2D
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


func add_to_stack(amount: int) -> int:
	## Adds `amount` to this stack up to MAX_STACK, returns the overflow.
	var room: int = MAX_STACK - count
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
		_: return SCRAP_COLOR


static func kind_color(k: int) -> Color:
	match k:
		Kind.MECHANISM: return MECHANISM_COLOR
		Kind.PLATING: return PLATING_COLOR
		Kind.DATACORE: return DATACORE_COLOR
		Kind.CHARGE_CELL: return CHARGE_CELL_COLOR
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
		_:
			return "scrap"


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
		_:
			return "loose salvaged metal"


static func stack_label(k: int, amount: int) -> String:
	return "%s x%d" % [kind_name(k), amount]


func _draw() -> void:
	var r := Rect2(-Vector2(SIZE_PX, SIZE_PX) * 0.5, Vector2(SIZE_PX, SIZE_PX))
	if _atlas != null:
		var source := Rect2(Vector2(kind * 16, 0), ITEM_REGION_SIZE)
		draw_texture_rect_region(_atlas, Rect2(-ITEM_REGION_SIZE * 0.5, ITEM_REGION_SIZE), source)
	else:
		draw_rect(r, color())
	if count > 1:
		var font: Font = ThemeDB.fallback_font
		var label: String = str(count)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, STACK_FONT_SIZE)
		var pos := Vector2(-text_size.x * 0.5, text_size.y * 0.32)
		draw_string_outline(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, STACK_FONT_SIZE, STACK_OUTLINE_SIZE, Color.BLACK)
		draw_string(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, STACK_FONT_SIZE, Color.WHITE)
