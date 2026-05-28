class_name AchievementToast
extends Control
##
## Full-screen achievement unlock notification. Shows on top of gameplay without
## pausing — click or wait 4.5 s to dismiss. Multiple unlocks are queued and
## shown one at a time. PROCESS_MODE_ALWAYS so it runs during pause.
##

const ORBITRON: Font = preload("res://resources/Orbitron-VariableFont_wght.ttf")
const ICON_ATLAS_PATH: String = "res://resources/ui/achievements_atlas.png"
const ICON_CELL: int = 32

const DISPLAY_SECONDS: float = 4.5
const SCALE_IN_SECONDS: float = 0.32
const FADE_OUT_SECONDS: float = 0.28

const PANEL_W: float = 380.0
const PANEL_H: float = 160.0

## Queued achievement ids waiting to be shown.
var _queue: Array[StringName] = []
var _showing: bool = false
## Wall-clock msec when the current modal started showing (set by _show_next).
var _show_start_msec: int = 0
## Active modal panel (freed on dismiss).
var _modal: Control = null
## Current border-pulse tween; killed and replaced on each new modal.
var _border_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 600
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


## Handles click-to-dismiss at the input level, bypassing GUI filter hierarchy.
## Using gui_input on the overlay doesn't work because inner Controls (labels,
## panel) have MOUSE_FILTER_STOP by default and absorb clicks before they reach
## the overlay's gui_input handler.
func _input(event: InputEvent) -> void:
	if not _showing:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_dismiss()


func _on_achievement_unlocked(id: StringName) -> void:
	_queue.append(id)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		return
	var id: StringName = _queue.pop_front()
	var ach_index: int = -1
	var ach: Dictionary = {}
	for i in AchievementManager.ACHIEVEMENTS.size():
		var a: Dictionary = AchievementManager.ACHIEVEMENTS[i] as Dictionary
		if a.get("id", &"") as StringName == id:
			ach = a
			ach_index = i
			break
	if ach.is_empty():
		_show_next()
		return

	_showing = true
	_show_start_msec = Time.get_ticks_msec()
	_modal = _build_modal(ach, ach_index)
	add_child(_modal)
	_animate_in(_modal)


## _process drives all animation using real wall-clock time so it works even
## when Engine.time_scale == 0 (game paused). PROCESS_MODE_ALWAYS ensures
## this runs regardless of the scene tree's pause state.
func _process(_delta: float) -> void:
	if not _showing or _modal == null or not is_instance_valid(_modal):
		return
	var elapsed: float = (Time.get_ticks_msec() - _show_start_msec) / 1000.0
	if elapsed < SCALE_IN_SECONDS:
		var t: float = elapsed / SCALE_IN_SECONDS
		_modal.scale = Vector2.ONE * lerpf(0.7, 1.0, t)
		_modal.modulate.a = clampf(t / 0.8, 0.0, 1.0)
	else:
		_modal.scale = Vector2.ONE
		_modal.modulate.a = 1.0
	if elapsed >= SCALE_IN_SECONDS + DISPLAY_SECONDS:
		_dismiss()


func _dismiss() -> void:
	if _border_tween != null:
		_border_tween.kill()
		_border_tween = null
	if _modal == null or not is_instance_valid(_modal):
		_modal = null
		_showing = false
		_show_next()
		return
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_showing = false
	_show_next()


func _animate_in(panel: Control) -> void:
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0


func _build_modal(ach: Dictionary, index: int) -> Control:
	# Use explicit pixel sizes so positioning is correct immediately, without
	# waiting for anchor-based layout to propagate (avoids top-left flash).
	var vp_size: Vector2 = get_viewport_rect().size

	var overlay := Control.new()
	overlay.size = vp_size
	overlay.position = Vector2.ZERO
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.pivot_offset = vp_size * 0.5

	# Semi-transparent background dimmer.
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.0, 0.0, 0.0, 0.52)
	dimmer.size = vp_size
	dimmer.position = Vector2.ZERO
	overlay.add_child(dimmer)

	# Centered panel — positioned explicitly so layout order doesn't matter.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.position = Vector2((vp_size.x - PANEL_W) * 0.5, (vp_size.y - PANEL_H) * 0.5)
	panel.pivot_offset = Vector2(PANEL_W * 0.5, PANEL_H * 0.5)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.065, 0.98)
	style.border_color = Color(0.90, 0.76, 0.22, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.90, 0.76, 0.22, 0.40)
	style.shadow_size = 20
	style.shadow_offset = Vector2.ZERO
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Header row: label + AP badge.
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 0)
	vbox.add_child(header_row)

	var header_lbl := Label.new()
	header_lbl.text = "ACHIEVEMENT UNLOCKED"
	header_lbl.add_theme_font_override("font", ORBITRON)
	header_lbl.add_theme_font_size_override("font_size", 9)
	header_lbl.add_theme_color_override("font_color", Color(0.90, 0.76, 0.22, 1.0))
	header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_lbl)

	var pts_lbl := Label.new()
	pts_lbl.text = "+%d AP" % int(ach.get("points", 0))
	pts_lbl.add_theme_font_override("font", ORBITRON)
	pts_lbl.add_theme_font_size_override("font_size", 14)
	pts_lbl.add_theme_color_override("font_color", Color(0.96, 0.88, 0.40, 1.0))
	header_row.add_child(pts_lbl)

	# Icon + name row.
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 14)
	vbox.add_child(body_row)

	var icon_tex: Texture2D = _achievement_icon(index)
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(54, 54)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body_row.add_child(icon_rect)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 4)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body_row.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = str(ach.get("name", "???"))
	name_lbl.add_theme_font_override("font", ORBITRON)
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	text_col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(ach.get("desc", ""))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.62, 0.70, 0.76))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_lbl)

	# Dismiss hint.
	var hint_lbl := Label.new()
	hint_lbl.text = "Click to continue"
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.54, 0.80))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint_lbl)

	# Golden border pulse animation driven by a tween looping on the panel.
	_start_border_pulse(panel, style)

	return overlay


func _start_border_pulse(panel: PanelContainer, style: StyleBoxFlat) -> void:
	if _border_tween != null:
		_border_tween.kill()
	_border_tween = create_tween()
	_border_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_border_tween.set_loops()
	_border_tween.tween_method(func(v: float) -> void:
		style.shadow_color = Color(0.90, 0.76, 0.22, v)
		style.shadow_size = int(14.0 + 10.0 * v)
		style.border_color = Color(0.90 + 0.10 * v, 0.76 + 0.14 * v, 0.22, 1.0)
	, 0.3, 1.0, 0.7).set_ease(Tween.EASE_IN_OUT)
	_border_tween.tween_method(func(v: float) -> void:
		style.shadow_color = Color(0.90, 0.76, 0.22, v)
		style.shadow_size = int(14.0 + 10.0 * v)
		style.border_color = Color(0.90 + 0.10 * v, 0.76 + 0.14 * v, 0.22, 1.0)
	, 1.0, 0.3, 0.7).set_ease(Tween.EASE_IN_OUT)


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
