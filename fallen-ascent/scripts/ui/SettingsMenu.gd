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
@onready var _master_value: Label = %MasterValue
@onready var _music_value: Label = %MusicValue
@onready var _sfx_value: Label = %SfxValue
@onready var _controls_list: VBoxContainer = %ControlsList
@onready var _capture_label: Label = %CaptureLabel
@onready var _close_button: Button = %CloseButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton

var _binding_action: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if _tabs != null:
		_tabs.set_tab_title(0, "Display")
		if _tabs.get_tab_count() > 1:
			_tabs.set_tab_title(1, "Audio")
		if _tabs.get_tab_count() > 2:
			_tabs.set_tab_title(2, "Controls")

	_initialize_display_mode()
	_initialize_resolution()
	_initialize_vsync()
	_initialize_fps()
	_initialize_ui_scale()
	_initialize_darkness()
	_initialize_swap_mouse()
	_initialize_audio()
	_rebuild_controls()

	_close_button.pressed.connect(_close)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_main_menu_button.visible = _is_in_game()

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
	_update_volume_label(_master_value, SettingsManager.master_volume)
	_update_volume_label(_music_value, SettingsManager.music_volume)
	_update_volume_label(_sfx_value, SettingsManager.sfx_volume)
	_master_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)


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
