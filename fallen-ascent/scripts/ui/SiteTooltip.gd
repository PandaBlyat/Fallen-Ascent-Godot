extends Control
##
## Hover tooltip for the world map. Follows the mouse with a small offset.
##

const FOLLOW_OFFSET := Vector2(16, 16)

@onready var label: Label = $Panel/Label

var _visible_site: bool = false


func _ready() -> void:
	hide_tooltip()


func _process(_delta: float) -> void:
	if not _visible_site:
		return
	position = get_viewport().get_mouse_position() + FOLLOW_OFFSET


func show_for(site: SiteData) -> void:
	_visible_site = true
	visible = true
	label.text = "%s\nseed: %d\nscore: %.2f" % [
		SiteData.biome_name(site.biome),
		site.site_seed,
		site.score,
	]


func hide_tooltip() -> void:
	_visible_site = false
	visible = false
