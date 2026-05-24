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

enum Kind { SCRAP, COMPONENT, SUBSTRATE, CIRCUIT, POWER_CELL }

const SCRAP_COLOR := Color(0.85, 0.75, 0.25)
const COMPONENT_COLOR := Color(0.55, 0.75, 0.95)
const SUBSTRATE_COLOR := Color(0.7, 0.95, 0.55)
const CIRCUIT_COLOR := Color(0.45, 1.0, 0.82)
const POWER_CELL_COLOR := Color(0.95, 0.45, 1.0)
const SIZE_PX: float = 8.0
const MAX_STACK: int = 16

var kind: int = Kind.SCRAP
var grid: Vector2i = Vector2i.ZERO
var count: int = 1
var reserved_by: Node = null


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
		Kind.COMPONENT: return COMPONENT_COLOR
		Kind.SUBSTRATE: return SUBSTRATE_COLOR
		Kind.CIRCUIT: return CIRCUIT_COLOR
		Kind.POWER_CELL: return POWER_CELL_COLOR
		_: return SCRAP_COLOR


static func kind_color(k: int) -> Color:
	match k:
		Kind.COMPONENT: return COMPONENT_COLOR
		Kind.SUBSTRATE: return SUBSTRATE_COLOR
		Kind.CIRCUIT: return CIRCUIT_COLOR
		Kind.POWER_CELL: return POWER_CELL_COLOR
		_: return SCRAP_COLOR


static func kind_name(k: int) -> String:
	match k:
		Kind.COMPONENT:
			return "component"
		Kind.SUBSTRATE:
			return "substrate"
		Kind.CIRCUIT:
			return "circuit"
		Kind.POWER_CELL:
			return "power cell"
		_:
			return "scrap"


func _draw() -> void:
	var r := Rect2(-Vector2(SIZE_PX, SIZE_PX) * 0.5, Vector2(SIZE_PX, SIZE_PX))
	draw_rect(r, color())
	if count > 1:
		var font: Font = ThemeDB.fallback_font
		var label: String = str(count)
		var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		draw_string(font, Vector2(-size.x * 0.5, size.y * 0.3), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.BLACK)
