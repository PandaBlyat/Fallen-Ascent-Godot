extends Node2D
##
## Renders the world overview map and handles click-to-select.
##
## Visuals are intentionally placeholder: each cell is a flat-color rect drawn
## via `_draw()`. When we have real art, swap the body of `_draw()` for a
## TileMapLayer; the rest of this file shouldn't need to change.

@export var grid_size: Vector2i = Vector2i(32, 18)
@export var cell_pixels: int = 32
@export var cell_inset: int = 1  ## visible gap between cells in pixels

@onready var tooltip: Control = $TooltipLayer/SiteTooltip

var _sites: Array[SiteData] = []
var _hovered_index: int = -1


func _ready() -> void:
	_sites = WorldGenerator.generate(GameState.world_seed, grid_size)
	queue_redraw()


func _draw() -> void:
	for i in _sites.size():
		var site: SiteData = _sites[i]
		var origin := Vector2(site.grid_pos) * cell_pixels
		var rect := Rect2(
			origin + Vector2(cell_inset, cell_inset),
			Vector2(cell_pixels - cell_inset * 2, cell_pixels - cell_inset * 2),
		)
		draw_rect(rect, SiteData.biome_color(site.biome))

		if i == _hovered_index:
			draw_rect(rect, Color(1, 1, 1, 0.9), false, 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event.is_action_pressed("select_site"):
		_try_select(get_local_mouse_position())


func _update_hover(screen_pos: Vector2) -> void:
	var local: Vector2 = to_local(screen_pos + Vector2.ZERO)  # this node has no transform
	var idx: int = _index_at(local)
	if idx == _hovered_index:
		return
	_hovered_index = idx
	if idx >= 0:
		tooltip.show_for(_sites[idx])
	else:
		tooltip.hide_tooltip()
	queue_redraw()


func _try_select(local_pos: Vector2) -> void:
	var idx: int = _index_at(local_pos)
	if idx < 0:
		return
	GameState.set_selected_site(_sites[idx])
	get_tree().change_scene_to_file("res://scenes/colony/ColonySite.tscn")


func _index_at(local_pos: Vector2) -> int:
	var gx: int = int(floor(local_pos.x / cell_pixels))
	var gy: int = int(floor(local_pos.y / cell_pixels))
	if gx < 0 or gy < 0 or gx >= grid_size.x or gy >= grid_size.y:
		return -1
	return gy * grid_size.x + gx
