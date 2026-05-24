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

var display_mode: int = DisplayMode.WINDOWED
var vsync_mode: int = VSyncMode.ENABLED
var max_fps: int = 0


func _ready() -> void:
	load_from_disk()
	apply()


func set_display_mode(mode: int) -> void:
	if mode == display_mode:
		return
	display_mode = mode
	apply()
	save_to_disk()
	settings_changed.emit()


func set_vsync_mode(mode: int) -> void:
	if mode == vsync_mode:
		return
	vsync_mode = mode
	apply()
	save_to_disk()
	settings_changed.emit()


func set_max_fps(fps: int) -> void:
	if fps == max_fps:
		return
	max_fps = fps
	apply()
	save_to_disk()
	settings_changed.emit()


func apply() -> void:
	# Order matters on some platforms: clear fullscreen first, then update
	# flags, then re-enter the target mode. This avoids the case where
	# switching from exclusive fullscreen leaves the window in a stale state
	# with no visible mode change.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_BORDERLESS,
		display_mode == DisplayMode.BORDERLESS,
	)
	DisplayServer.window_set_mode(_to_window_mode(display_mode))
	DisplayServer.window_set_vsync_mode(_to_vsync_mode(vsync_mode))
	Engine.max_fps = max(0, max_fps)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	display_mode = int(cfg.get_value(SECTION_DISPLAY, "display_mode", display_mode))
	vsync_mode = int(cfg.get_value(SECTION_DISPLAY, "vsync_mode", vsync_mode))
	max_fps = int(cfg.get_value(SECTION_DISPLAY, "max_fps", max_fps))


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_DISPLAY, "display_mode", display_mode)
	cfg.set_value(SECTION_DISPLAY, "vsync_mode", vsync_mode)
	cfg.set_value(SECTION_DISPLAY, "max_fps", max_fps)
	cfg.save(CONFIG_PATH)


func _to_window_mode(mode: int) -> int:
	# BORDERLESS = bordered-less windowed (size unchanged, no decorations).
	# FULLSCREEN = "windowed fullscreen" / borderless-fullscreen — works
	# more reliably across platforms than exclusive fullscreen.
	match mode:
		DisplayMode.FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_WINDOWED


func _to_vsync_mode(mode: int) -> int:
	match mode:
		VSyncMode.DISABLED:
			return DisplayServer.VSYNC_DISABLED
		VSyncMode.ADAPTIVE:
			return DisplayServer.VSYNC_ADAPTIVE
		_:
			return DisplayServer.VSYNC_ENABLED
