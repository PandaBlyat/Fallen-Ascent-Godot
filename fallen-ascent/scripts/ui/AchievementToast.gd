class_name AchievementToast
extends Control
##
## Screen-space achievement unlock toast. Attach to any scene or CanvasLayer.
## Connects to EventBus.achievement_unlocked automatically on _ready.
## PROCESS_MODE_ALWAYS so toasts display even when game speed is paused.
##

const ORBITRON: Font = preload("res://resources/Orbitron-VariableFont_wght.ttf")
const ICON_ATLAS_PATH: String = "res://resources/ui/achievements_atlas.png"
const ICON_CELL: int = 32

const DISPLAY_SECONDS: float = 5.0
const SLIDE_IN_SECONDS: float = 0.38
const FADE_OUT_SECONDS: float = 0.4
const PANEL_WIDTH: float = 290.0
const MARGIN: float = 14.0
const STACK_GAP: float = 6.0

## Tracks how many panels are currently alive so each new one stacks below.
var _active_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 500
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


func _on_achievement_unlocked(id: StringName) -> void:
	for i in AchievementManager.ACHIEVEMENTS.size():
		var ach: Dictionary = AchievementManager.ACHIEVEMENTS[i] as Dictionary
		if ach.get("id", &"") as StringName == id:
			_spawn_toast(ach, i)
			return


func _spawn_toast(ach: Dictionary, index: int) -> void:
	var panel := _build_panel(ach, index)
	add_child(panel)

	# Wait one frame for the panel to calculate its natural size.
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return

	var vp_size: Vector2 = get_viewport_rect().size
	var panel_h: float = maxf(panel.size.y, 70.0)
	var target_x: float = vp_size.x - PANEL_WIDTH - MARGIN
	var start_x: float  = vp_size.x + 10.0
	var y_pos: float    = MARGIN + float(_active_count) * (panel_h + STACK_GAP)

	panel.position = Vector2(start_x, y_pos)
	panel.custom_minimum_size.x = PANEL_WIDTH

	_active_count += 1

	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.tween_property(panel, "position:x", target_x, SLIDE_IN_SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(DISPLAY_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_OUT_SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_active_count = maxi(0, _active_count - 1)
		panel.queue_free()
	)


func _build_panel(ach: Dictionary, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.08, 0.97)
	style.border_color = Color(0.90, 0.76, 0.22, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	# --- Icon ---
	var icon_tex: Texture2D = _achievement_icon(index)
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(38, 38)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(icon_rect)

	# --- Text column ---
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var header := Label.new()
	header.text = "ACHIEVEMENT UNLOCKED"
	header.add_theme_font_override("font", ORBITRON)
	header.add_theme_font_size_override("font_size", 8)
	header.add_theme_color_override("font_color", Color(0.90, 0.76, 0.22, 1.0))
	vbox.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = str(ach.get("name", "???"))
	name_lbl.add_theme_font_override("font", ORBITRON)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(ach.get("desc", ""))
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.add_theme_color_override("font_color", Color(0.62, 0.70, 0.76))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	# --- AP badge ---
	var pts_lbl := Label.new()
	pts_lbl.text = "+%d AP" % int(ach.get("points", 0))
	pts_lbl.add_theme_font_override("font", ORBITRON)
	pts_lbl.add_theme_font_size_override("font_size", 11)
	pts_lbl.add_theme_color_override("font_color", Color(0.84, 0.78, 0.46))
	pts_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(pts_lbl)

	return panel


static func _achievement_icon(index: int) -> Texture2D:
	if not ResourceLoader.exists(ICON_ATLAS_PATH):
		return null
	var tex: Texture2D = load(ICON_ATLAS_PATH) as Texture2D
	if tex == null:
		return null
	var cols: int = maxi(1, int(tex.get_width() / ICON_CELL))
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(
		(index % cols) * ICON_CELL,
		int(index / cols) * ICON_CELL,
		ICON_CELL, ICON_CELL)
	return atlas
