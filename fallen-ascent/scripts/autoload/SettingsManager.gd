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

enum DisplayMode { WINDOWED, BORDERLESS, FULLSCREEN }
enum VSyncMode { DISABLED, ENABLED, ADAPTIVE }

const FPS_PRESETS: Array[int] = [30, 60, 120, 144, 165, 240, 0]
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)

var display_mode: int = DisplayMode.WINDOWED
var vsync_mode: int = VSyncMode.ENABLED
var max_fps: int = 0


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


func apply() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	match display_mode:
		DisplayMode.WINDOWED:
			DisplayServer.window_set_size(DEFAULT_WINDOW_SIZE)
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


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_DISPLAY, "display_mode", display_mode)
	cfg.set_value(SECTION_DISPLAY, "vsync_mode", vsync_mode)
	cfg.set_value(SECTION_DISPLAY, "max_fps", max_fps)
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
	DisplayServer.window_set_position(screen_pos + (screen_size - DEFAULT_WINDOW_SIZE) / 2)
