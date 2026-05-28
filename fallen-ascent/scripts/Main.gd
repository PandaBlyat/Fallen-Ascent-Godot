extends Control
##
## Main menu. New Game pops up a small panel asking for seed (optional, blank
## = random) and world size; the seed/size are stashed on GameState before the
## Colony scene loads. World map selection is skipped.
##

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/SettingsMenu.tscn")

const MAP_SIZE_OPTIONS: Array = [
	{"label": "Tiny",    "chunks": Vector2i(6, 6),   "hint": "fastest"},
	{"label": "Small",   "chunks": Vector2i(9, 9),   "hint": "light"},
	{"label": "Medium",  "chunks": Vector2i(12, 12), "hint": "balanced"},
	{"label": "Default", "chunks": Vector2i(16, 16), "hint": "larger"},
	{"label": "High, I hear fans spinning", "chunks": Vector2i(24, 24), "hint": "stress test"},
]
const DEFAULT_MAP_SIZE_INDEX: int = 2

@onready var _new_game_button: Button = %NewGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _background: TextureRect = $Background
@onready var _buttons: VBoxContainer = $Buttons


func _ready() -> void:
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_add_continue_button()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	MenuMusicPlayer.play_once_from_start()


## Adds a Continue button at the top of the menu when a colony save exists, so
## the player can resume directly without opening Settings.
func _add_continue_button() -> void:
	if not SaveManager.has_save():
		return
	var button := Button.new()
	button.text = "Continue"
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 16)
	_buttons.add_child(button)
	_buttons.move_child(button, 0)
	button.pressed.connect(AudioManager.play_button_press)
	button.pressed.connect(func() -> void: SaveManager.begin_load())

func _on_new_game_pressed() -> void:
	if has_node("NewGameDialog"):
		return
	add_child(_build_new_game_dialog())


func _on_settings_pressed() -> void:
	if has_node("SettingsMenu"):
		return
	var menu := SETTINGS_MENU_SCENE.instantiate()
	menu.name = "SettingsMenu"
	add_child(menu)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _resolve_seed_from_text(text: String) -> int:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		# Honour the --seed=<int> dev override only when the player leaves the
		# seed field blank, so manual entries take precedence.
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--seed="):
				return arg.substr("--seed=".length()).to_int()
		return randi()
	if trimmed.is_valid_int():
		return trimmed.to_int()
	# Allow free-form strings (e.g. "BLAME!"); hash gives us a stable int seed.
	return hash(trimmed)


func _build_new_game_dialog() -> Control:
	var overlay := Control.new()
	overlay.name = "NewGameDialog"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.55)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dimmer)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260.0
	panel.offset_top = -200.0
	panel.offset_right = 260.0
	panel.offset_bottom = 200.0
	panel.add_theme_stylebox_override("panel", _dialog_style())
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "New Game"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 0.96, 1.0))
	vbox.add_child(title)

	var seed_label := Label.new()
	seed_label.text = "Seed (optional — leave blank for random)"
	seed_label.add_theme_font_size_override("font_size", 12)
	seed_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.84, 1.0))
	vbox.add_child(seed_label)

	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "%d" % randi()
	seed_edit.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(seed_edit)

	var size_label := Label.new()
	size_label.text = "World size"
	size_label.add_theme_font_size_override("font_size", 12)
	size_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.84, 1.0))
	vbox.add_child(size_label)

	var size_options := OptionButton.new()
	size_options.custom_minimum_size = Vector2(0, 32)
	for i in MAP_SIZE_OPTIONS.size():
		var opt: Dictionary = MAP_SIZE_OPTIONS[i]
		var chunks: Vector2i = opt["chunks"] as Vector2i
		size_options.add_item("%s  (%dx%d chunks — %s)" % [opt["label"], chunks.x, chunks.y, opt["hint"]], i)
	size_options.select(DEFAULT_MAP_SIZE_INDEX)
	vbox.add_child(size_options)

	vbox.add_child(_dialog_spacer())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	vbox.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(110, 36)
	cancel.pressed.connect(overlay.queue_free)
	buttons.add_child(cancel)

	var start := Button.new()
	start.text = "Start"
	start.custom_minimum_size = Vector2(140, 36)
	start.pressed.connect(func() -> void:
		_start_game(seed_edit.text, size_options.get_selected_id())
	)
	buttons.add_child(start)

	return overlay


func _start_game(seed_text: String, size_index: int) -> void:
	var seed_value: int = _resolve_seed_from_text(seed_text)
	GameState.set_world_seed(seed_value)
	GameState.set_game_speed(1.0)
	var idx: int = clampi(size_index, 0, MAP_SIZE_OPTIONS.size() - 1)
	GameState.requested_map_size_chunks = MAP_SIZE_OPTIONS[idx]["chunks"] as Vector2i
	# Build a synthetic SiteData so ColonySite can boot without the world map.
	var site := SiteData.new()
	site.site_seed = hash([seed_value, "auto_site"])
	site.grid_pos = Vector2i.ZERO
	site.biome = SiteData.Biome.HABITAT
	GameState.set_selected_site(site)
	get_tree().change_scene_to_file("res://scenes/colony/ColonySite.tscn")


static func _dialog_style() -> StyleBox:
	const PANEL_PATH := "res://resources/ui/panels/selection_panel.png"
	if ResourceLoader.exists(PANEL_PATH):
		var tex: Texture2D = load(PANEL_PATH) as Texture2D
		if tex != null:
			var tex_style := StyleBoxTexture.new()
			tex_style.texture = tex
			tex_style.texture_margin_left = 16.0
			tex_style.texture_margin_top = 16.0
			tex_style.texture_margin_right = 16.0
			tex_style.texture_margin_bottom = 16.0
			return tex_style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.075, 0.085, 0.96)
	style.border_color = Color(0.32, 0.38, 0.42, 0.7)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


static func _dialog_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer
