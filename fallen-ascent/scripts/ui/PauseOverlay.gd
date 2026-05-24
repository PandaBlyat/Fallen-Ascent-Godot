extends Node
##
## In-game listener for `cancel_mode` (Esc). Cancels active gameplay input
## first (designation mode, then worker selection), then opens settings.
##

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/SettingsMenu.tscn")

@export var designator_path: NodePath
@export var selection_controller_path: NodePath

var _designator: Designator
var _selection_controller: SelectionController


func _ready() -> void:
	_designator = get_node_or_null(designator_path) as Designator
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel_mode"):
		return
	if has_node("SettingsMenu"):
		return
	if _designator != null and _designator.cancel_active():
		get_viewport().set_input_as_handled()
		return
	if _selection_controller != null and _selection_controller.clear_selection():
		get_viewport().set_input_as_handled()
		return
	var menu := SETTINGS_MENU_SCENE.instantiate()
	menu.name = "SettingsMenu"
	add_child(menu)
	get_viewport().set_input_as_handled()
