extends Node
##
## Global display / graphics settings. Loaded from user://settings.cfg on
## boot, applied to the DisplayServer + Engine before any scene renders.
##
## Read fields directly; mutate ONLY through set_* setters so changes are
## applied, persisted, and broadcast in one step.
##

signal settings_changed

const CONFIG_PATH := "user://settings.cfg"
const SECTION_DISPLAY := "display"
const SECTION_AUDIO := "audio"
const SECTION_INPUT := "input"
const SECTION_GAMEPLAY := "gameplay"

enum DisplayMode { WINDOWED, BORDERLESS, FULLSCREEN }
enum VSyncMode { DISABLED, ENABLED, ADAPTIVE }

const FPS_PRESETS: Array[int] = [30, 60, 120, 144, 165, 240, 0]
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"cam_up",
	&"cam_down",
	&"cam_left",
	&"cam_right",
	&"cam_drag",
	&"select_site",
	&"pause_toggle",
	&"speed_pause",
	&"speed_1x",
	&"speed_2x",
	&"speed_3x",
	&"speed_10x",
	&"designate_mine",
	&"designate_stockpile",
	&"designate_remove_stockpile",
	&"designate_build",
	&"designate_build_door",
	&"designate_build_extractor",
	&"cancel_mode",
]

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_AMBIENT := &"Ambient"

var display_mode: int = DisplayMode.WINDOWED
var vsync_mode: int = VSyncMode.ENABLED
var max_fps: int = 0
var window_size: Vector2i = DEFAULT_WINDOW_SIZE
var ui_scale: float = 1.0
## Audio volumes are linear [0.0, 1.0]; 1.0 == 0dB on the bus.
## Music default starts at 0.5 (≈-6dB) per the menu music ask.
var master_volume: float = 1.0
var music_volume: float = 0.5
var sfx_volume: float = 1.0
var ambient_volume: float = 0.8
## Gameplay options.
## When true, left-click drives designation/place/cancel and right-click
## drives camera-world selection. When false (default), left-click selects
## and right-click drives designation/orders.
var swap_mouse_buttons: bool = false
## Multiplier applied on top of fog-of-war alpha. 1.0 = stock; 0.5 = half
## as dark; 1.5 = darker. Clamped to [0.0, 2.0].
var overall_darkness: float = 1.0


func _ready() -> void:
	load_from_disk()
	apply()


func set_display_mode(mode: int) -> void:
	mode = clampi(mode, DisplayMode.WINDOWED, DisplayMode.FULLSCREEN)
	if mode == display_mode:
		apply()
		return
	display_mode = mode
	apply()
	save_to_disk()
	settings_changed.emit()


func set_vsync_mode(mode: int) -> void:
	mode = clampi(mode, VSyncMode.DISABLED, VSyncMode.ADAPTIVE)
	if mode == vsync_mode:
		apply()
		return
	vsync_mode = mode
	apply()
	save_to_disk()
	settings_changed.emit()


func set_max_fps(fps: int) -> void:
	if fps == max_fps:
		apply()
		return
	max_fps = fps
	apply()
	save_to_disk()
	settings_changed.emit()


func set_window_size(size: Vector2i) -> void:
	size.x = clampi(size.x, 640, 7680)
	size.y = clampi(size.y, 360, 4320)
	if size == window_size:
		apply()
		return
	window_size = size
	apply()
	save_to_disk()
	settings_changed.emit()


func set_ui_scale(value: float) -> void:
	value = clampf(value, 0.75, 2.0)
	if is_equal_approx(value, ui_scale):
		apply()
		return
	ui_scale = value
	apply()
	save_to_disk()
	settings_changed.emit()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_MASTER, master_volume)
	save_to_disk()
	settings_changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	save_to_disk()
	settings_changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	save_to_disk()
	settings_changed.emit()


func set_ambient_volume(value: float) -> void:
	ambient_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BUS_AMBIENT, ambient_volume)
	save_to_disk()
	settings_changed.emit()


func set_swap_mouse_buttons(value: bool) -> void:
	if swap_mouse_buttons == value:
		return
	swap_mouse_buttons = value
	save_to_disk()
	settings_changed.emit()


## The mouse button used for "select / cancel / clear" (default left).
## Returns the user-configured value, swapping LMB↔RMB when
## `swap_mouse_buttons` is on.
func primary_mouse_button() -> int:
	return MOUSE_BUTTON_RIGHT if swap_mouse_buttons else MOUSE_BUTTON_LEFT


## The mouse button used for "place / order / drag" (default right).
func secondary_mouse_button() -> int:
	return MOUSE_BUTTON_LEFT if swap_mouse_buttons else MOUSE_BUTTON_RIGHT


func set_overall_darkness(value: float) -> void:
	value = clampf(value, 0.0, 2.0)
	if is_equal_approx(value, overall_darkness):
		return
	overall_darkness = value
	save_to_disk()
	settings_changed.emit()


func apply() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	match display_mode:
		DisplayMode.WINDOWED:
			DisplayServer.window_set_size(window_size)
			_center_window()
		DisplayMode.BORDERLESS:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	DisplayServer.window_set_vsync_mode(_to_vsync_mode(vsync_mode))
	Engine.max_fps = max(0, max_fps)
	get_tree().root.content_scale_factor = ui_scale

	_apply_bus_volume(BUS_MASTER, master_volume)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	_apply_bus_volume(BUS_AMBIENT, ambient_volume)


func set_action_key(action: StringName, event: InputEventKey) -> void:
	if not InputMap.has_action(action):
		return
	var key_event := InputEventKey.new()
	key_event.keycode = event.keycode
	key_event.physical_keycode = event.physical_keycode
	key_event.key_label = event.key_label
	key_event.location = event.location
	key_event.ctrl_pressed = event.ctrl_pressed
	key_event.alt_pressed = event.alt_pressed
	key_event.shift_pressed = event.shift_pressed
	key_event.meta_pressed = event.meta_pressed
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, key_event)
	save_to_disk()
	settings_changed.emit()


func action_key_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).as_text_physical_keycode()
		if event is InputEventMouseButton:
			return event.as_text()
	return "Unbound"


func action_display_name(action: StringName) -> String:
	var text: String = String(action).replace("_", " ")
	return text.capitalize()


func _apply_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	if linear <= 0.0001:
		AudioServer.set_bus_mute(idx, true)
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	display_mode = clampi(
		int(cfg.get_value(SECTION_DISPLAY, "display_mode", display_mode)),
		DisplayMode.WINDOWED,
		DisplayMode.FULLSCREEN,
	)
	vsync_mode = clampi(
		int(cfg.get_value(SECTION_DISPLAY, "vsync_mode", vsync_mode)),
		VSyncMode.DISABLED,
		VSyncMode.ADAPTIVE,
	)
	max_fps = int(cfg.get_value(SECTION_DISPLAY, "max_fps", max_fps))
	ui_scale = clampf(float(cfg.get_value(SECTION_DISPLAY, "ui_scale", ui_scale)), 0.75, 2.0)
	var saved_size: Variant = cfg.get_value(SECTION_DISPLAY, "window_size", window_size)
	if saved_size is Vector2i:
		window_size = saved_size as Vector2i
	elif saved_size is Vector2:
		var saved_vec := saved_size as Vector2
		window_size = Vector2i(int(saved_vec.x), int(saved_vec.y))
	master_volume = clampf(float(cfg.get_value(SECTION_AUDIO, "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value(SECTION_AUDIO, "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value(SECTION_AUDIO, "sfx_volume", sfx_volume)), 0.0, 1.0)
	ambient_volume = clampf(float(cfg.get_value(SECTION_AUDIO, "ambient_volume", ambient_volume)), 0.0, 1.0)
	swap_mouse_buttons = bool(cfg.get_value(SECTION_GAMEPLAY, "swap_mouse_buttons", swap_mouse_buttons))
	overall_darkness = clampf(float(cfg.get_value(SECTION_GAMEPLAY, "overall_darkness", overall_darkness)), 0.0, 2.0)
	_load_keybindings(cfg)


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_DISPLAY, "display_mode", display_mode)
	cfg.set_value(SECTION_DISPLAY, "vsync_mode", vsync_mode)
	cfg.set_value(SECTION_DISPLAY, "max_fps", max_fps)
	cfg.set_value(SECTION_DISPLAY, "window_size", window_size)
	cfg.set_value(SECTION_DISPLAY, "ui_scale", ui_scale)
	cfg.set_value(SECTION_AUDIO, "master_volume", master_volume)
	cfg.set_value(SECTION_AUDIO, "music_volume", music_volume)
	cfg.set_value(SECTION_AUDIO, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION_AUDIO, "ambient_volume", ambient_volume)
	cfg.set_value(SECTION_GAMEPLAY, "swap_mouse_buttons", swap_mouse_buttons)
	cfg.set_value(SECTION_GAMEPLAY, "overall_darkness", overall_darkness)
	_save_keybindings(cfg)
	cfg.save(CONFIG_PATH)


func _to_vsync_mode(mode: int) -> int:
	match mode:
		VSyncMode.DISABLED:
			return DisplayServer.VSYNC_DISABLED
		VSyncMode.ADAPTIVE:
			return DisplayServer.VSYNC_ADAPTIVE
		_:
			return DisplayServer.VSYNC_ENABLED


func _center_window() -> void:
	var screen: int = DisplayServer.window_get_current_screen()
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(screen_pos + (screen_size - window_size) / 2)


func _load_keybindings(cfg: ConfigFile) -> void:
	for action in REBINDABLE_ACTIONS:
		if not cfg.has_section_key(SECTION_INPUT, String(action)):
			continue
		var data: Variant = cfg.get_value(SECTION_INPUT, String(action))
		if not (data is Dictionary):
			continue
		var dict := data as Dictionary
		var event := InputEventKey.new()
		event.keycode = int(dict.get("keycode", 0))
		event.physical_keycode = int(dict.get("physical_keycode", 0))
		event.key_label = int(dict.get("key_label", 0))
		event.location = int(dict.get("location", 0))
		event.ctrl_pressed = bool(dict.get("ctrl", false))
		event.alt_pressed = bool(dict.get("alt", false))
		event.shift_pressed = bool(dict.get("shift", false))
		event.meta_pressed = bool(dict.get("meta", false))
		if event.keycode == 0 and event.physical_keycode == 0:
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


func _save_keybindings(cfg: ConfigFile) -> void:
	for action in REBINDABLE_ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := event as InputEventKey
				cfg.set_value(SECTION_INPUT, String(action), {
					"keycode": key.keycode,
					"physical_keycode": key.physical_keycode,
					"key_label": key.key_label,
					"location": key.location,
					"ctrl": key.ctrl_pressed,
					"alt": key.alt_pressed,
					"shift": key.shift_pressed,
					"meta": key.meta_pressed,
				})
				break
