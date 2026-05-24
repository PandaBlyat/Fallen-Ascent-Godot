extends CanvasLayer

## Emitted when the settings menu is closed, allowing parent menus
## to restore focus or resume the game.
signal closed

const FPS_LABELS: Array[String] = ["30", "60", "120", "144", "165", "240", "Unlimited"]
const MAIN_MENU_SCENE_PATH := "res://scenes/Main.tscn"

@onready var _tabs: TabContainer = %Tabs
@onready var _display_mode_button: OptionButton = %DisplayModeButton
@onready var _vsync_button: OptionButton = %VSyncButton
@onready var _fps_button: OptionButton = %MaxFpsButton
@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _master_value: Label = %MasterValue
@onready var _music_value: Label = %MusicValue
@onready var _sfx_value: Label = %SfxValue
@onready var _close_button: Button = %CloseButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if _tabs != null:
		_tabs.set_tab_title(0, "Display")
		if _tabs.get_tab_count() > 1:
			_tabs.set_tab_title(1, "Audio")

	_initialize_display_mode()
	_initialize_vsync()
	_initialize_fps()
	_initialize_audio()

	_close_button.pressed.connect(_close)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_main_menu_button.visible = _is_in_game()

	# Grab focus on the first element to support controller and keyboard navigation
	_display_mode_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
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


func _on_display_mode_selected(index: int) -> void:
	SettingsManager.set_display_mode(_display_mode_button.get_item_id(index))


func _on_vsync_selected(index: int) -> void:
	SettingsManager.set_vsync_mode(_vsync_button.get_item_id(index))


func _on_fps_selected(index: int) -> void:
	if index < SettingsManager.FPS_PRESETS.size():
		SettingsManager.set_max_fps(SettingsManager.FPS_PRESETS[index])


func _on_main_menu_pressed() -> void:
	GameState.set_game_speed(1.0)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _is_in_game() -> bool:
	# Hide the "Main Menu" button when we are already on the main menu.
	var current: Node = get_tree().current_scene
	if current == null:
		return false
	return current.scene_file_path != MAIN_MENU_SCENE_PATH


func _close() -> void:
	closed.emit()
	queue_free()


func _select_item_id(button: OptionButton, item_id: int) -> void:
	for i in button.item_count:
		if button.get_item_id(i) == item_id:
			button.select(i)
			return
	button.select(0)
