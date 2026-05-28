class_name FpsOverlay
extends CanvasLayer
## A self-contained utility that draws a styled FPS counter in the top-right corner.
## To use: Instantiate this class and add it as a child to your main scene.

var _label: Label

func _ready() -> void:
	# High layer value ensures this renders on top of standard game UI layers
	layer = 128
	
	# Margin container for corner positioning
	var margin_container := MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin_container.offset_left = -120.0
	margin_container.offset_top = 10.0
	margin_container.offset_right = -10.0
	margin_container.offset_bottom = 36.0
	margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin_container)

	# Semi-transparent background panel matching the existing UI aesthetic
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.09, 0.82)
	style.border_color = Color(0.22, 0.48, 0.55, 0.45)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)
	margin_container.add_child(panel)

	# Internal padding for text alignment
	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 8)
	padding.add_theme_constant_override("margin_top", 3)
	padding.add_theme_constant_override("margin_right", 8)
	padding.add_theme_constant_override("margin_bottom", 3)
	panel.add_child(padding)

	# Setup the label text
	_label = Label.new()
	_label.text = "FPS: --"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.42, 0.85, 0.92)) # Cyan accent
	padding.add_child(_label)


func _process(_delta: float) -> void:
	if _label != null:
		_label.text = "FPS: %d" % Engine.get_frames_per_second()
