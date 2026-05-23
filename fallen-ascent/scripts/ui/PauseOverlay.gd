extends Node
##
## In-game listener for `cancel_mode` (Esc). Opens the settings menu when
## no designation mode is consuming the event first. Lives under the
## ColonySite HUD CanvasLayer; relies on Designator to consume Esc when a
## mode is active (Designator only calls set_input_as_handled when its
## mode != NONE).
##

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/SettingsMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel_mode"):
		return
	if has_node("SettingsMenu"):
		return
	var menu := SETTINGS_MENU_SCENE.instantiate()
	menu.name = "SettingsMenu"
	add_child(menu)
	get_viewport().set_input_as_handled()
