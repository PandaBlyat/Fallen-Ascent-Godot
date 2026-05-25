extends CanvasLayer
##
## Modal panel showing the tech tree. Built code-side to match the rest of
## the colony HUD; layout is driven by TechData.grid_position.
##

const CELL_SIZE := Vector2(170.0, 110.0)
const NODE_SIZE := Vector2(150.0, 90.0)
const COLOR_BG_DARK := Color(0.045, 0.052, 0.06, 0.96)
const COLOR_BG_PANEL := Color(0.07, 0.085, 0.10, 0.98)
const COLOR_TEXT_LIGHT := Color(0.92, 0.96, 0.97, 1.0)
const COLOR_TEXT_MUTED := Color(0.68, 0.75, 0.78, 1.0)
const COLOR_TEXT_DIM := Color(0.46, 0.50, 0.55, 1.0)
const COLOR_ACCENT_AMBER := Color(0.96, 0.58, 0.16, 1.0)
const COLOR_WISDOM := Color(0.82, 0.78, 1.0, 1.0)
const COLOR_UNLOCKED := Color(0.38, 0.78, 0.46, 0.85)
const COLOR_AVAILABLE := Color(0.96, 0.58, 0.16, 0.85)
const COLOR_AVAILABLE_DIM := Color(0.96, 0.58, 0.16, 0.35)
const COLOR_LOCKED := Color(0.30, 0.34, 0.38, 0.6)
const COLOR_LINE_LOCKED := Color(0.30, 0.34, 0.38, 0.55)
const COLOR_LINE_UNLOCKED := Color(0.38, 0.78, 0.46, 0.7)

var _wisdom_label: Label
var _graph: Control
var _nodes_root: Control
var _node_buttons: Dictionary = {}                   ## StringName -> PanelContainer


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.62)
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -460.0
	panel.offset_top = -300.0
	panel.offset_right = 460.0
	panel.offset_bottom = 300.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", _textured_panel_style("tech_tree", COLOR_BG_PANEL))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Technology"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_wisdom_label = Label.new()
	_wisdom_label.add_theme_font_size_override("font_size", 14)
	_wisdom_label.add_theme_color_override("font_color", COLOR_WISDOM)
	header.add_child(_wisdom_label)

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(80, 28)
	close.add_theme_font_size_override("font_size", 12)
	close.pressed.connect(_close)
	header.add_child(close)

	var subtitle := Label.new()
	subtitle.text = "Bots meditating in a Meditation Chamber generate wisdom. Spend wisdom to unlock new structures."
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(CELL_SIZE.x * 6.0 + 40.0, CELL_SIZE.y * 5.0 + 40.0)
	_graph.draw.connect(_on_graph_draw)
	scroll.add_child(_graph)

	_nodes_root = Control.new()
	_nodes_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nodes_root.anchor_right = 1.0
	_nodes_root.anchor_bottom = 1.0
	_graph.add_child(_nodes_root)

	_build_nodes()
	_refresh_wisdom_label()

	EventBus.wisdom_changed.connect(_on_wisdom_changed)
	EventBus.tech_unlocked.connect(_on_tech_unlocked)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel_mode"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	queue_free()


func _build_nodes() -> void:
	for tech in TechDatabase.all():
		var node := _make_tech_button(tech)
		_nodes_root.add_child(node)
		_node_buttons[tech.id] = node
	_refresh_nodes()


func _make_tech_button(tech: TechData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = NODE_SIZE
	panel.size = NODE_SIZE
	var origin := _node_origin(tech)
	panel.position = origin
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("tech_id", tech.id)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var branch_label := Label.new()
	branch_label.text = tech.branch_label.to_lower()
	branch_label.add_theme_font_size_override("font_size", 9)
	branch_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	box.add_child(branch_label)

	var name_label := Label.new()
	name_label.text = tech.display_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = "%d wisdom" % tech.wisdom_cost if tech.wisdom_cost > 0 else "starter"
	cost_label.add_theme_font_size_override("font_size", 10)
	cost_label.add_theme_color_override("font_color", COLOR_WISDOM)
	box.add_child(cost_label)

	var desc_label := Label.new()
	desc_label.text = tech.description
	desc_label.add_theme_font_size_override("font_size", 9)
	desc_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc_label)

	panel.gui_input.connect(_on_node_input.bind(tech.id))
	return panel


func _node_origin(tech: TechData) -> Vector2:
	return Vector2(
		20.0 + float(tech.grid_position.x) * CELL_SIZE.x,
		20.0 + float(tech.grid_position.y) * CELL_SIZE.y,
	)


func _node_center(tech: TechData) -> Vector2:
	return _node_origin(tech) + NODE_SIZE * 0.5


func _on_node_input(event: InputEvent, tech_id: StringName) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_unlock(tech_id)


func _try_unlock(tech_id: StringName) -> void:
	if TechManager == null:
		return
	if TechManager.is_unlocked(tech_id):
		return
	if not TechManager.can_unlock(tech_id):
		return
	TechManager.try_unlock(tech_id)


func _refresh_nodes() -> void:
	for tech in TechDatabase.all():
		var node: PanelContainer = _node_buttons.get(tech.id) as PanelContainer
		if node == null:
			continue
		var state: int = _state_for(tech.id)
		node.add_theme_stylebox_override("panel", _node_style(state))
	if _graph != null:
		_graph.queue_redraw()


func _state_for(tech_id: StringName) -> int:
	# 0 locked-prereq, 1 affordable, 2 unaffordable-but-available, 3 unlocked.
	if TechManager == null:
		return 0
	if TechManager.is_unlocked(tech_id):
		return 3
	if not TechManager.prerequisites_met(tech_id):
		return 0
	var tech: TechData = TechDatabase.by_id(tech_id)
	if tech == null:
		return 0
	if TechManager.wisdom >= float(tech.wisdom_cost):
		return 1
	return 2


func _node_style(state: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.set_border_width_all(1)
	match state:
		3:
			style.border_color = COLOR_UNLOCKED
		1:
			style.border_color = COLOR_AVAILABLE
		2:
			style.border_color = COLOR_AVAILABLE_DIM
		_:
			style.border_color = COLOR_LOCKED
	return style


func _panel_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(1)
	style.border_color = Color(0.28, 0.34, 0.38, 0.6)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


## See `resources/ui/panels/README.md`. Tech-tree-specific panels read
## their backgrounds from the shared placeholder PNG library so swapping
## in real art is just a file replacement.
func _textured_panel_style(panel_name: String, fallback_bg: Color) -> StyleBox:
	var path: String = "res://resources/ui/panels/%s.png" % panel_name
	if not ResourceLoader.exists(path):
		return _panel_style(fallback_bg)
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return _panel_style(fallback_bg)
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = 16.0
	style.texture_margin_top = 16.0
	style.texture_margin_right = 16.0
	style.texture_margin_bottom = 16.0
	return style


func _on_graph_draw() -> void:
	if _graph == null:
		return
	for tech in TechDatabase.all():
		for prereq_id in tech.prerequisites:
			var prereq: TechData = TechDatabase.by_id(prereq_id)
			if prereq == null:
				continue
			var color: Color = COLOR_LINE_LOCKED
			if TechManager != null and TechManager.is_unlocked(prereq.id) and TechManager.is_unlocked(tech.id):
				color = COLOR_LINE_UNLOCKED
			elif TechManager != null and TechManager.is_unlocked(prereq.id):
				color = Color(COLOR_AVAILABLE.r, COLOR_AVAILABLE.g, COLOR_AVAILABLE.b, 0.55)
			var from_pos: Vector2 = _node_origin(prereq) + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5)
			var to_pos: Vector2 = _node_origin(tech) + Vector2(0.0, NODE_SIZE.y * 0.5)
			_graph.draw_line(from_pos, to_pos, color, 1.0, true)


func _refresh_wisdom_label() -> void:
	if _wisdom_label != null and TechManager != null:
		_wisdom_label.text = "wisdom: %d" % int(roundf(TechManager.wisdom))


func _on_wisdom_changed(_new_total: float) -> void:
	_refresh_wisdom_label()
	_refresh_nodes()


func _on_tech_unlocked(_tech_id: StringName) -> void:
	_refresh_wisdom_label()
	_refresh_nodes()
