extends Control
##
## Main menu. New Game opens the Embark screen, then the seed/size dialog;
## both are stashed on GameState before the Colony scene loads.
## World map selection is skipped.
##

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/SettingsMenu.tscn")
const EMBARK_SCREEN_SCRIPT: Script = preload("res://scripts/ui/EmbarkScreen.gd")
const ACHIEVEMENT_TOAST_SCRIPT: Script = preload("res://scripts/ui/AchievementToast.gd")

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
	# Skin every button below this root with the shared worker-card texture so the
	# main menu (and its dialogs) match the rest of the game's UI chrome.
	theme = UiStyle.button_theme()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_add_continue_button()
	_add_achievements_button()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_new_game_button.pressed.connect(AudioManager.play_button_press)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_button.pressed.connect(AudioManager.play_button_press)
	_quit_button.pressed.connect(_on_quit_pressed)
	_quit_button.pressed.connect(AudioManager.play_button_press)
	MenuMusicPlayer.play_once_from_start()
	var _toast := ACHIEVEMENT_TOAST_SCRIPT.new() as Control
	_toast.name = "AchievementToast"
	add_child(_toast)


## Adds a Continue button at the top of the menu when a colony save exists, so
## the player can open the save list panel and resume or delete saves.
func _add_continue_button() -> void:
	if not SaveManager.has_save():
		return
	var button := Button.new()
	button.text = "Load Save"
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 16)
	_buttons.add_child(button)
	_buttons.move_child(button, 0)
	button.pressed.connect(AudioManager.play_button_press)
	button.pressed.connect(func() -> void:
		if has_node("SaveListPanel"):
			return
		add_child(_build_save_list_panel())
	)


## Adds an Achievements button below the main menu buttons.
func _add_achievements_button() -> void:
	var button := Button.new()
	button.text = "Achievements"
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 14)
	_buttons.add_child(button)
	button.pressed.connect(AudioManager.play_button_press)
	button.pressed.connect(_on_achievements_pressed)


func _on_achievements_pressed() -> void:
	if has_node("AchievementPanel"):
		return
	add_child(_build_achievement_panel())


func _on_new_game_pressed() -> void:
	if has_node("EmbarkScreen") or has_node("NewGameDialog"):
		return
	_open_embark_screen()


func _open_embark_screen() -> void:
	var embark: Control = EMBARK_SCREEN_SCRIPT.new() as Control
	embark.name = "EmbarkScreen"
	add_child(embark)
	# EmbarkScreen calls queue_free on itself; we stash the chosen crew builds on
	# GameState (consumed by WorkerSpawner) and open the next dialog.
	embark.embark_confirmed.connect(func(loadouts: Array) -> void:
		GameState.embark_loadouts = loadouts
		if not has_node("NewGameDialog"):
			add_child(_build_new_game_dialog())
	)


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
	cancel.text = "Back"
	cancel.custom_minimum_size = Vector2(110, 36)
	cancel.pressed.connect(AudioManager.play_button_press)
	cancel.pressed.connect(overlay.queue_free)
	buttons.add_child(cancel)

	var start := Button.new()
	start.text = "Start"
	start.custom_minimum_size = Vector2(140, 36)
	start.pressed.connect(AudioManager.play_button_press)
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
	AchievementManager.on_new_game_started()
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


## Builds the save-file list panel so the player can resume or delete saves.
func _build_save_list_panel() -> Control:
	var overlay := Control.new()
	overlay.name = "SaveListPanel"
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
	panel.offset_left = -280.0
	panel.offset_top = -240.0
	panel.offset_right = 280.0
	panel.offset_bottom = 240.0
	panel.add_theme_stylebox_override("panel", _dialog_style())
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Load Save"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 0.96, 1.0))
	vbox.add_child(title)

	var saves: Array[Dictionary] = SaveManager.list_saves()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	if saves.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No save files found."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.63))
		list.add_child(empty_lbl)
	else:
		for entry in saves:
			var row := _build_save_row(entry, overlay)
			list.add_child(row)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var spacer_ctrl := Control.new()
	spacer_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer_ctrl)

	var close_btn := Button.new()
	close_btn.text = "Cancel"
	close_btn.custom_minimum_size = Vector2(110, 36)
	close_btn.pressed.connect(AudioManager.play_button_press)
	close_btn.pressed.connect(overlay.queue_free)
	btn_row.add_child(close_btn)

	return overlay


func _build_save_row(entry: Dictionary, overlay: Control) -> Control:
	var path: String = str(entry.get("path", ""))
	var modified: int = int(entry.get("modified_unix", 0))
	var size_bytes: int = int(entry.get("size_bytes", 0))

	var row_bg := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.10, 0.12, 0.14, 0.80)
	row_style.set_border_width_all(1)
	row_style.border_color = Color(0.22, 0.28, 0.32, 0.55)
	row_style.set_corner_radius_all(4)
	row_bg.add_theme_stylebox_override("panel", row_style)

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 10)
	row_margin.add_theme_constant_override("margin_top", 8)
	row_margin.add_theme_constant_override("margin_right", 8)
	row_margin.add_theme_constant_override("margin_bottom", 8)
	row_bg.add_child(row_margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row_margin.add_child(hbox)

	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 2)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_col)

	var date_str: String = "Unknown date"
	if modified > 0:
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(modified)
		date_str = "%04d-%02d-%02d  %02d:%02d" % [
			int(dt.get("year", 0)), int(dt.get("month", 0)), int(dt.get("day", 0)),
			int(dt.get("hour", 0)), int(dt.get("minute", 0))
		]

	var name_lbl := Label.new()
	name_lbl.text = path.get_file().get_basename().replace("_", " ").capitalize()
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.95))
	info_col.add_child(name_lbl)

	var date_lbl := Label.new()
	date_lbl.text = date_str
	date_lbl.add_theme_font_size_override("font_size", 10)
	date_lbl.add_theme_color_override("font_color", Color(0.56, 0.63, 0.68))
	info_col.add_child(date_lbl)

	var size_lbl := Label.new()
	size_lbl.text = "%d KB" % (size_bytes / 1024)
	size_lbl.add_theme_font_size_override("font_size", 10)
	size_lbl.add_theme_color_override("font_color", Color(0.42, 0.48, 0.52))
	info_col.add_child(size_lbl)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(80, 32)
	resume_btn.pressed.connect(AudioManager.play_button_press)
	resume_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		SaveManager.begin_load(path)
	)
	hbox.add_child(resume_btn)

	# Two-click delete: first click arms, second confirms.
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(70, 32)
	del_btn.add_theme_color_override("font_color", Color(0.78, 0.38, 0.34))
	del_btn.set_meta("armed", false)
	del_btn.pressed.connect(func() -> void:
		if not del_btn.get_meta("armed", false):
			del_btn.set_meta("armed", true)
			del_btn.text = "Sure?"
			del_btn.add_theme_color_override("font_color", Color(1.0, 0.28, 0.22))
			del_btn.get_tree().create_timer(2.5, false).timeout.connect(func() -> void:
				if is_instance_valid(del_btn):
					del_btn.set_meta("armed", false)
					del_btn.text = "Delete"
					del_btn.add_theme_color_override("font_color", Color(0.78, 0.38, 0.34))
			)
		else:
			SaveManager.delete_save(path)
			row_bg.queue_free()
	)
	hbox.add_child(del_btn)

	return row_bg


## Builds the achievements panel overlay (shows unlocked/locked achievements).
func _build_achievement_panel() -> Control:
	var overlay := Control.new()
	overlay.name = "AchievementPanel"
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
	panel.offset_left = -300.0
	panel.offset_top = -260.0
	panel.offset_right = 300.0
	panel.offset_bottom = 260.0
	panel.add_theme_stylebox_override("panel", _dialog_style())
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Achievements"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 0.96))
	vbox.add_child(title)

	# Achievement-point wallet: earned lifetime, minus what's been permanently
	# spent on tier / crew unlocks in the embark screen.
	var points_row := Label.new()
	points_row.text = "Achievement Points: %d available  ·  %d earned  ·  %d spent" % [
		AchievementManager.available_points(),
		AchievementManager.total_points(),
		AchievementManager.spent_points(),
	]
	points_row.add_theme_font_size_override("font_size", 12)
	points_row.add_theme_color_override("font_color", Color(0.84, 0.78, 0.46))
	vbox.add_child(points_row)

	var hint := Label.new()
	hint.text = "Spend points on the Embark screen to unlock higher part tiers and extra workers."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.56, 0.62, 0.66))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 340)
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var achievements: Array = AchievementManager.all_achievements()

	var unlocked_count: int = 0
	for i in achievements.size():
		var ach: Dictionary = achievements[i] as Dictionary
		var is_unlocked: bool = bool(ach.get("unlocked", false))
		if is_unlocked:
			unlocked_count += 1
		var row := _build_achievement_row(ach, is_unlocked, i)
		list.add_child(row)

	var summary := Label.new()
	summary.text = "Unlocked: %d / %d" % [unlocked_count, achievements.size()]
	summary.add_theme_font_size_override("font_size", 11)
	summary.add_theme_color_override("font_color", Color(0.62, 0.70, 0.74))
	vbox.add_child(summary)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	# Spacer so reset sits on the left and close on the right.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	# Two-click confirmation: first press arms it; second press within 3s resets.
	# State is stored on the button via metadata so the lambda captures it by ref.
	var reset_btn := Button.new()
	reset_btn.text = "Reset Achievements"
	reset_btn.custom_minimum_size = Vector2(160, 36)
	reset_btn.add_theme_color_override("font_color", Color(0.70, 0.40, 0.36))
	reset_btn.set_meta("armed", false)
	reset_btn.pressed.connect(func() -> void:
		if not reset_btn.get_meta("armed", false):
			reset_btn.set_meta("armed", true)
			reset_btn.text = "Confirm reset? (click again)"
			reset_btn.add_theme_color_override("font_color", Color(1.0, 0.30, 0.25))
			var t: SceneTreeTimer = reset_btn.get_tree().create_timer(3.0, false)
			t.timeout.connect(func() -> void:
				if is_instance_valid(reset_btn):
					reset_btn.set_meta("armed", false)
					reset_btn.text = "Reset Achievements"
					reset_btn.add_theme_color_override("font_color", Color(0.70, 0.40, 0.36))
			)
		else:
			AchievementManager.reset_achievements()
			overlay.queue_free()
	)
	btn_row.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(110, 36)
	close_btn.pressed.connect(AudioManager.play_button_press)
	close_btn.pressed.connect(overlay.queue_free)
	btn_row.add_child(close_btn)

	return overlay


const ACHIEVEMENT_ICON_ATLAS: String = "res://resources/ui/achievements_atlas.png"
const ACHIEVEMENT_ICON_CELL: int = 32


static func _build_achievement_row(ach: Dictionary, unlocked: bool, index: int) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	# Placeholder per-achievement art from the icon atlas; locked entries are
	# dimmed. Falls back to a colored chip if the atlas isn't present.
	var icon_tex: Texture2D = _achievement_icon(index)
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.modulate = Color.WHITE if unlocked else Color(0.30, 0.32, 0.34, 0.85)
		hbox.add_child(icon_rect)
	else:
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.color = Color(0.32, 0.85, 0.48, 1.0) if unlocked else Color(0.28, 0.30, 0.32, 1.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = str(ach.get("name", "???"))
	name_lbl.add_theme_font_size_override("font_size", 12)
	var name_color: Color = Color(0.90, 0.94, 0.92) if unlocked else Color(0.40, 0.44, 0.46)
	name_lbl.add_theme_color_override("font_color", name_color)
	col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(ach.get("desc", "")) if unlocked else "???"
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.52, 0.58, 0.62))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc_lbl)

	var points_lbl := Label.new()
	points_lbl.text = "+%d AP" % int(ach.get("points", 0))
	points_lbl.add_theme_font_size_override("font_size", 11)
	points_lbl.add_theme_color_override("font_color",
		Color(0.84, 0.78, 0.46) if unlocked else Color(0.42, 0.44, 0.40))
	points_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(points_lbl)

	return hbox


## One 32x32 cell from the achievement icon atlas, indexed left-to-right.
## Returns null if the atlas is missing so the caller can fall back.
static func _achievement_icon(index: int) -> Texture2D:
	if not ResourceLoader.exists(ACHIEVEMENT_ICON_ATLAS):
		return null
	var tex: Texture2D = load(ACHIEVEMENT_ICON_ATLAS) as Texture2D
	if tex == null:
		return null
	var cols: int = maxi(1, int(tex.get_width() / ACHIEVEMENT_ICON_CELL))
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(
		(index % cols) * ACHIEVEMENT_ICON_CELL,
		int(index / cols) * ACHIEVEMENT_ICON_CELL,
		ACHIEVEMENT_ICON_CELL, ACHIEVEMENT_ICON_CELL)
	return atlas
