extends Control
##
## Main menu. Hands off to the world map on New Game (picking a world seed,
## random by default, override with `--seed=<int>` for reproducible dev
## runs), opens the settings overlay on Settings, exits on Quit.
##

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/SettingsMenu.tscn")

@onready var _new_game_button: Button = %NewGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_new_game_pressed() -> void:
	GameState.set_world_seed(_resolve_seed())
	GameState.set_game_speed(1.0)
	get_tree().change_scene_to_file("res://scenes/world/WorldMap.tscn")


func _on_settings_pressed() -> void:
	if has_node("SettingsMenu"):
		return
	var menu := SETTINGS_MENU_SCENE.instantiate()
	menu.name = "SettingsMenu"
	add_child(menu)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _resolve_seed() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return arg.substr("--seed=".length()).to_int()
	return randi()
