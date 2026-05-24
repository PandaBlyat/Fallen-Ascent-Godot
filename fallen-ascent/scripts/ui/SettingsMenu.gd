extends CanvasLayer
##
## Graphics settings overlay. Reads current values from SettingsManager,
## writes back through its setters. Reusable from both the main menu and
## the in-game pause overlay — instance the scene and add it as a child.
##

const FPS_LABELS: Array[String] = ["30", "60", "120", "144", "165", "240", "Unlimited"]

@onready var _display_mode_button: OptionButton = %DisplayModeButton
@onready var _vsync_button: OptionButton = %VSyncButton
@onready var _fps_button: OptionButton = %MaxFpsButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_display_mode_button.clear()
	_display_mode_button.add_item("Windowed", SettingsManager.DisplayMode.WINDOWED)
	_display_mode_button.add_item("Borderless", SettingsManager.DisplayMode.BORDERLESS)
	_display_mode_button.add_item("Fullscreen", SettingsManager.DisplayMode.FULLSCREEN)
	_select_item_id(_display_mode_button, SettingsManager.display_mode)
	_display_mode_button.item_selected.connect(_on_display_mode_selected)

	_vsync_button.clear()
	_vsync_button.add_item("Disabled", SettingsManager.VSyncMode.DISABLED)
	_vsync_button.add_item("Enabled", SettingsManager.VSyncMode.ENABLED)
	_vsync_button.add_item("Adaptive", SettingsManager.VSyncMode.ADAPTIVE)
	_select_item_id(_vsync_button, SettingsManager.vsync_mode)
	_vsync_button.item_selected.connect(_on_vsync_selected)

	_fps_button.clear()
	for i in SettingsManager.FPS_PRESETS.size():
		_fps_button.add_item(FPS_LABELS[i], i)
	var current_fps_index := SettingsManager.FPS_PRESETS.find(SettingsManager.max_fps)
	if current_fps_index == -1:
		current_fps_index = SettingsManager.FPS_PRESETS.size() - 1
	_fps_button.select(current_fps_index)
	_fps_button.item_selected.connect(_on_fps_selected)

	_close_button.pressed.connect(_close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_mode"):
		get_viewport().set_input_as_handled()
		_close()


func _on_display_mode_selected(index: int) -> void:
	SettingsManager.set_display_mode(_display_mode_button.get_item_id(index))


func _on_vsync_selected(index: int) -> void:
	SettingsManager.set_vsync_mode(_vsync_button.get_item_id(index))


func _on_fps_selected(index: int) -> void:
	SettingsManager.set_max_fps(SettingsManager.FPS_PRESETS[index])


func _close() -> void:
	queue_free()


func _select_item_id(button: OptionButton, item_id: int) -> void:
	for i in button.item_count:
		if button.get_item_id(i) == item_id:
			button.select(i)
			return
	button.select(0)
