extends CanvasLayer

## Emitted when the settings menu is closed, allowing parent menus
## to restore focus or resume the game.
signal closed

const FPS_LABELS: Array[String] = ["30", "60", "120", "144", "165", "240", "Unlimited"]
const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
]
const MAIN_MENU_SCENE_PATH := "res://scenes/Main.tscn"
const SAVE_PATH := "user://save.tres"
const AUTOSAVE_PRESETS: Array[int] = [0, 60, 120, 300, 600]
const AUTOSAVE_LABELS: Array[String] = ["Off", "1 min", "2 min", "5 min", "10 min"]

@onready var _tabs: TabContainer = %Tabs
@onready var _display_mode_button: OptionButton = %DisplayModeButton
@onready var _resolution_button: OptionButton = %ResolutionButton
@onready var _vsync_button: OptionButton = %VSyncButton
@onready var _fps_button: OptionButton = %MaxFpsButton
@onready var _ui_scale_slider: HSlider = %UiScaleSlider
@onready var _ui_scale_value: Label = %UiScaleValue
@onready var _darkness_slider: HSlider = %DarknessSlider
@onready var _darkness_value: Label = %DarknessValue
@onready var _swap_mouse_check: CheckButton = %SwapMouseCheck
@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _ambient_slider: HSlider = %AmbientSlider
@onready var _master_value: Label = %MasterValue
@onready var _music_value: Label = %MusicValue
@onready var _sfx_value: Label = %SfxValue
@onready var _ambient_value: Label = %AmbientValue
@onready var _controls_list: VBoxContainer = %ControlsList
@onready var _capture_label: Label = %CaptureLabel
@onready var _close_button: Button = %CloseButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton
@onready var _autosave_button: OptionButton = %AutosaveButton
@onready var _edge_panning_check: CheckButton = %EdgePanningCheck
@onready var _pan_speed_slider: HSlider = %PanSpeedSlider
@onready var _pan_speed_value: Label = %PanSpeedValue
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton

var _binding_action: StringName = &""


@onready var _root_panel: PanelContainer = $Panel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Skin the settings buttons with the shared worker-card texture (CanvasLayer
	# can't hold a theme, so apply it to the root panel that holds the controls).
	if _root_panel != null:
		_root_panel.theme = UiStyle.button_theme()

	if _tabs != null:
		_tabs.set_tab_title(0, "Display")
		if _tabs.get_tab_count() > 1:
			_tabs.set_tab_title(1, "Audio")
		if _tabs.get_tab_count() > 2:
			_tabs.set_tab_title(2, "Controls")
		if _tabs.get_tab_count() > 3:
			_tabs.set_tab_title(3, "Gameplay")

	_initialize_display_mode()
	_initialize_resolution()
	_initialize_vsync()
	_initialize_fps()
	_initialize_ui_scale()
	_initialize_darkness()
	_initialize_swap_mouse()
	_initialize_audio()
	_rebuild_controls()
	_initialize_gameplay()

	_close_button.pressed.connect(_close)
	_close_button.pressed.connect(AudioManager.play_button_press)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_main_menu_button.pressed.connect(AudioManager.play_button_press)
	_quit_button.pressed.connect(_on_quit_pressed)
	_quit_button.pressed.connect(AudioManager.play_button_press)
	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)

	var in_game := _is_in_game()
	_main_menu_button.visible = in_game
	# Saving needs a running colony; loading works from the main menu too so the
	# player can resume a saved colony without starting a new game first.
	_save_button.visible = in_game
	_load_button.visible = true
	_load_button.disabled = not _save_exists()

	# Grab focus on the first element to support controller and keyboard navigation
	_display_mode_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Handle key and mouse rebinding
	if not _binding_action.is_empty():
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			get_viewport().set_input_as_handled()
			
			var is_escape := false
			if event is InputEventKey:
				is_escape = (event.physical_keycode == KEY_ESCAPE)
			
			# If Escape is pressed, cancel the rebinding process
			if not is_escape:
				SettingsManager.set_action_key(_binding_action, event)
			
			_binding_action = &""
			_rebuild_controls()
		return
		
	# "ui_cancel" is the Godot default for back/escape actions
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel_mode"):
		get_viewport().set_input_as_handled()
		_close()


func _initialize_display_mode() -> void:
	_display_mode_button.clear()
	_display_mode_button.add_item("Windowed", SettingsManager.DisplayMode.WINDOWED)
	_display_mode_button.add_item("Borderless", SettingsManager.DisplayMode.BORDERLESS)
	_display_mode_button.add_item("Fullscreen", SettingsManager.DisplayMode.FULLSCREEN)
	_select_item_id(_display_mode_button, SettingsManager.display_mode)
	_display_mode_button.item_selected.connect(_on_display_mode_selected)
	_update_resolution_enabled()


func _initialize_resolution() -> void:
	_resolution_button.clear()
	for i in RESOLUTION_PRESETS.size():
		var size: Vector2i = RESOLUTION_PRESETS[i]
		_resolution_button.add_item("%d x %d" % [size.x, size.y], i)
	var current_index: int = _resolution_index(SettingsManager.window_size)
	_resolution_button.select(current_index)
	_resolution_button.item_selected.connect(_on_resolution_selected)
	_update_resolution_enabled()


func _initialize_vsync() -> void:
	_vsync_button.clear()
	_vsync_button.add_item("Disabled", SettingsManager.VSyncMode.DISABLED)
	_vsync_button.add_item("Enabled", SettingsManager.VSyncMode.ENABLED)
	_vsync_button.add_item("Adaptive", SettingsManager.VSyncMode.ADAPTIVE)
	_select_item_id(_vsync_button, SettingsManager.vsync_mode)
	_vsync_button.item_selected.connect(_on_vsync_selected)


func _initialize_fps() -> void:
	_fps_button.clear()

	# Safe iteration checking size boundaries between labels and presets
	var preset_count := SettingsManager.FPS_PRESETS.size()
	for i in preset_count:
		var label := FPS_LABELS[i] if i < FPS_LABELS.size() else str(SettingsManager.FPS_PRESETS[i])
		_fps_button.add_item(label, i)

	var current_fps_index := SettingsManager.FPS_PRESETS.find(SettingsManager.max_fps)
	if current_fps_index == -1:
		current_fps_index = preset_count - 1

	_fps_button.select(current_fps_index)
	_fps_button.item_selected.connect(_on_fps_selected)


func _initialize_ui_scale() -> void:
	_ui_scale_slider.min_value = 0.75
	_ui_scale_slider.max_value = 2.0
	_ui_scale_slider.step = 0.25 # Stepped to prevent muddy/blurry pixel-art scaling
	_ui_scale_slider.value = SettingsManager.ui_scale
	_update_ui_scale_label(SettingsManager.ui_scale)
	_ui_scale_slider.value_changed.connect(_on_ui_scale_changed)


func _initialize_darkness() -> void:
	_darkness_slider.min_value = 0.0
	_darkness_slider.max_value = 2.0
	_darkness_slider.step = 0.05
	_darkness_slider.value = SettingsManager.overall_darkness
	_update_darkness_label(SettingsManager.overall_darkness)
	_darkness_slider.value_changed.connect(_on_darkness_changed)


func _initialize_swap_mouse() -> void:
	_swap_mouse_check.button_pressed = SettingsManager.swap_mouse_buttons
	_swap_mouse_check.toggled.connect(_on_swap_mouse_toggled)


func _initialize_audio() -> void:
	_master_slider.value = SettingsManager.master_volume
	_music_slider.value = SettingsManager.music_volume
	_sfx_slider.value = SettingsManager.sfx_volume
	_ambient_slider.value = SettingsManager.ambient_volume
	_update_volume_label(_master_value, SettingsManager.master_volume)
	_update_volume_label(_music_value, SettingsManager.music_volume)
	_update_volume_label(_sfx_value, SettingsManager.sfx_volume)
	_update_volume_label(_ambient_value, SettingsManager.ambient_volume)
	_master_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_ambient_slider.value_changed.connect(_on_ambient_volume_changed)


func _rebuild_controls() -> void:
	if _controls_list == null:
		return
		
	# Free old elements immediately
	for child in _controls_list.get_children():
		child.queue_free()
		
	if _capture_label != null:
		if _binding_action.is_empty():
			_capture_label.text = ""
		else:
			_capture_label.text = "Press any key or mouse button for: " + SettingsManager.action_display_name(_binding_action) + "\n(Press Esc to Cancel)"

	for action in SettingsManager.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		
		var label := Label.new()
		label.text = SettingsManager.action_display_name(action)
		label.custom_minimum_size = Vector2(190, 0)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		
		if action == _binding_action:
			button.text = "Listening..."
			button.disabled = true
		else:
			button.text = SettingsManager.action_key_text(action)
			button.pressed.connect(_begin_rebind.bind(action))
			
		row.add_child(button)
		_controls_list.add_child(row)


func _begin_rebind(action: StringName) -> void:
	_binding_action = action
	_rebuild_controls()


func _on_master_volume_changed(value: float) -> void:
	SettingsManager.set_master_volume(value)
	_update_volume_label(_master_value, value)


func _on_music_volume_changed(value: float) -> void:
	SettingsManager.set_music_volume(value)
	_update_volume_label(_music_value, value)


func _on_sfx_volume_changed(value: float) -> void:
	SettingsManager.set_sfx_volume(value)
	_update_volume_label(_sfx_value, value)


func _on_ambient_volume_changed(value: float) -> void:
	SettingsManager.set_ambient_volume(value)
	_update_volume_label(_ambient_value, value)


func _update_volume_label(label: Label, value: float) -> void:
	if label == null:
		return
	label.text = "%d%%" % int(roundf(clampf(value, 0.0, 1.0) * 100.0))


func _update_ui_scale_label(value: float) -> void:
	if _ui_scale_value == null:
		return
	_ui_scale_value.text = "%.2fx" % clampf(value, 0.75, 2.0)


func _on_display_mode_selected(index: int) -> void:
	SettingsManager.set_display_mode(_display_mode_button.get_item_id(index))
	_update_resolution_enabled()


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < RESOLUTION_PRESETS.size():
		SettingsManager.set_window_size(RESOLUTION_PRESETS[index])


func _on_vsync_selected(index: int) -> void:
	SettingsManager.set_vsync_mode(_vsync_button.get_item_id(index))


func _on_fps_selected(index: int) -> void:
	if index < SettingsManager.FPS_PRESETS.size():
		SettingsManager.set_max_fps(SettingsManager.FPS_PRESETS[index])


func _on_ui_scale_changed(value: float) -> void:
	SettingsManager.set_ui_scale(value)
	_update_ui_scale_label(SettingsManager.ui_scale)


func _on_darkness_changed(value: float) -> void:
	SettingsManager.set_overall_darkness(value)
	_update_darkness_label(SettingsManager.overall_darkness)


func _on_swap_mouse_toggled(pressed: bool) -> void:
	SettingsManager.set_swap_mouse_buttons(pressed)


func _update_darkness_label(value: float) -> void:
	if _darkness_value == null:
		return
	_darkness_value.text = "%.2fx" % clampf(value, 0.0, 2.0)


func _initialize_gameplay() -> void:
	_autosave_button.clear()
	for i in AUTOSAVE_PRESETS.size():
		var lbl := AUTOSAVE_LABELS[i] if i < AUTOSAVE_LABELS.size() else str(AUTOSAVE_PRESETS[i])
		_autosave_button.add_item(lbl, i)
	var autosave_idx := AUTOSAVE_PRESETS.find(SettingsManager.autosave_interval)
	_autosave_button.select(maxi(autosave_idx, 0))
	_autosave_button.item_selected.connect(_on_autosave_selected)

	_edge_panning_check.button_pressed = SettingsManager.edge_panning_enabled
	_edge_panning_check.toggled.connect(_on_edge_panning_toggled)

	_pan_speed_slider.min_value = 100.0
	_pan_speed_slider.max_value = 2000.0
	_pan_speed_slider.step = 50.0
	_pan_speed_slider.value = SettingsManager.camera_pan_speed
	_update_pan_speed_label(SettingsManager.camera_pan_speed)
	_pan_speed_slider.value_changed.connect(_on_pan_speed_changed)


func _on_autosave_selected(index: int) -> void:
	if index < AUTOSAVE_PRESETS.size():
		SettingsManager.set_autosave_interval(AUTOSAVE_PRESETS[index])


func _on_edge_panning_toggled(pressed: bool) -> void:
	SettingsManager.set_edge_panning_enabled(pressed)


func _on_pan_speed_changed(value: float) -> void:
	SettingsManager.set_camera_pan_speed(value)
	_update_pan_speed_label(value)


func _update_pan_speed_label(value: float) -> void:
	if _pan_speed_value == null:
		return
	_pan_speed_value.text = "%d" % int(value)


func _on_save_pressed() -> void:
	if SaveManager.save_current_game():
		_save_button.text = "Saved!"
		_load_button.disabled = not _save_exists()
		# Restore the label after a moment so repeated saves still read clearly.
		get_tree().create_timer(1.2, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(_save_button):
				_save_button.text = "Save"
		)
	else:
		_save_button.text = "Save failed"


func _on_load_pressed() -> void:
	if not SaveManager.has_save():
		_load_button.text = "No save"
		return
	# Show a save-list panel rather than loading immediately.
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var root: Window = tree.root
	if root.has_node("SaveListPanel"):
		return
	var panel: Control = _build_save_list_panel()
	panel.name = "SaveListPanel"
	root.add_child(panel)


func _save_exists() -> bool:
	return SaveManager.has_save()


func _build_save_list_panel() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200

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
	panel.add_theme_stylebox_override("panel", _dialog_style_flat())
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
	scroll.custom_minimum_size = Vector2(0, 270)
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
	resume_btn.pressed.connect(func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
		SaveManager.begin_load(path)
	)
	hbox.add_child(resume_btn)

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


static func _dialog_style_flat() -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.075, 0.085, 0.96)
	style.border_color = Color(0.32, 0.38, 0.42, 0.7)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _on_main_menu_pressed() -> void:
	GameState.set_game_speed(1.0)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _is_in_game() -> bool:
	# Hide the "Main Menu" button when we are already on the main menu.
	var current: Node = get_tree().current_scene
	if current == null or not ("scene_file_path" in current):
		return false
	return current.scene_file_path != MAIN_MENU_SCENE_PATH


func _close() -> void:
	# Save settings on close instead of writing to disk during slider movements
	if SettingsManager.has_method("save_settings"):
		SettingsManager.save_settings()
	closed.emit()
	queue_free()


func _select_item_id(button: OptionButton, item_id: int) -> void:
	for i in button.item_count:
		if button.get_item_id(i) == item_id:
			button.select(i)
			return
	button.select(0)


func _resolution_index(size: Vector2i) -> int:
	for i in RESOLUTION_PRESETS.size():
		if RESOLUTION_PRESETS[i] == size:
			return i
	return 0


func _update_resolution_enabled() -> void:
	if _resolution_button == null:
		return
	_resolution_button.disabled = SettingsManager.display_mode != SettingsManager.DisplayMode.WINDOWED
