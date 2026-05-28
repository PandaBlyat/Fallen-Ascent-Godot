extends CanvasLayer
## Modal panel showing the tech tree. Built code-side to match the rest of
## the colony HUD. Layout is driven by TechData.grid_position.

const CELL_SIZE := Vector2(250.0, 130.0)
const NODE_SIZE := Vector2(210.0, 95.0)

# Sci-Fi / Cybernetic Palette
const COLOR_BG_DARK := Color(0.03, 0.04, 0.05, 0.98)
const COLOR_BG_PANEL := Color(0.05, 0.06, 0.08, 0.98)
const COLOR_BG_DETAILS := Color(0.04, 0.05, 0.06, 0.95)

const COLOR_TEXT_LIGHT := Color(0.90, 0.95, 0.98, 1.0)
const COLOR_TEXT_MUTED := Color(0.60, 0.68, 0.72, 1.0)
const COLOR_TEXT_DIM := Color(0.38, 0.44, 0.48, 1.0)

# Neon Alert & State Indicators
const COLOR_ACCENT_AMBER := Color(0.96, 0.58, 0.16, 1.0)
const COLOR_WISDOM := Color(0.68, 0.62, 1.0, 1.0)       # Cyber-purple
const COLOR_UNLOCKED := Color(0.20, 0.80, 0.45, 1.0)     # Decrypted green
const COLOR_AVAILABLE := Color(0.00, 0.75, 1.00, 1.0)     # Ready cyan
const COLOR_AVAILABLE_DIM := Color(0.00, 0.45, 0.70, 0.45)
const COLOR_LOCKED := Color(0.22, 0.25, 0.28, 0.8)

# Connection Lines
const COLOR_LINE_LOCKED := Color(0.18, 0.21, 0.24, 0.7)
const COLOR_LINE_AVAILABLE := Color(0.00, 0.75, 1.00, 0.35)
const COLOR_LINE_UNLOCKED := Color(0.20, 0.80, 0.45, 0.75)

var _wisdom_label: Label
var _graph: Control
var _nodes_root: Control
var _node_buttons: Dictionary = {} # StringName -> PanelContainer

# Class-level members for dynamic scrolling, selection, and inspector updates
var _scroll_container: ScrollContainer
var _inspector_panel: PanelContainer
var _inspector_title: Label
var _inspector_branch: Label
var _inspector_desc: Label
var _inspector_cost: Label
var _inspector_action_btn: Button
var _inspector_unlocks_container: VBoxContainer

var _selected_tech_id: StringName = &""
var _hovered_tech_id: StringName = &""

# Mouse drag state variables for grid panning
var _is_dragging := false
var _drag_start_pos := Vector2.ZERO
var _scroll_start_pos := Vector2.ZERO


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.65)
	dimmer.anchor_right = 1.0
	dimmer.anchor_bottom = 1.0
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	# Main background container frame
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -680.0
	panel.offset_top = -420.0
	panel.offset_right = 680.0
	panel.offset_bottom = 420.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", _textured_panel_style("tech_tree", COLOR_BG_PANEL))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# --- Header Block ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "MAIN INTERFACE // SCHEMATICS COG"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_wisdom_label = Label.new()
	_wisdom_label.add_theme_font_size_override("font_size", 13)
	_wisdom_label.add_theme_color_override("font_color", COLOR_WISDOM)
	header.add_child(_wisdom_label)

	var close := Button.new()
	close.text = "DISCONNECT"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(110, 28)
	close.add_theme_font_size_override("font_size", 11)
	close.pressed.connect(_close)
	if is_instance_valid(AudioManager):
		close.pressed.connect(AudioManager.play_button_press)
	header.add_child(close)

	var subtitle := Label.new()
	subtitle.text = "Sensory units meditating in localized chambers extract wisdom. Re-route units to decrypt complex infrastructure."
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	# --- Split Content View (Tree on Left, Inspector on Right) ---
	var content_split := HBoxContainer.new()
	content_split.add_theme_constant_override("separation", 16)
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_split)

	# 1. Left Section: Scrollable Tree Area
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_stretch_ratio = 2.8
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_split.add_child(_scroll_container)

	_graph = Control.new()
	_graph.custom_minimum_size = _calculate_graph_size()
	_graph.draw.connect(_on_graph_draw)
	_graph.gui_input.connect(_on_graph_gui_input)
	_scroll_container.add_child(_graph)

	_nodes_root = Control.new()
	_nodes_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nodes_root.anchor_right = 1.0
	_nodes_root.anchor_bottom = 1.0
	_graph.add_child(_nodes_root)

	# 2. Right Section: Context Inspector Panel
	_build_inspector_panel()
	content_split.add_child(_inspector_panel)

	# Initialize nodes and connect to events
	_build_nodes()
	_refresh_wisdom_label()
	_update_inspector()

	EventBus.wisdom_changed.connect(_on_wisdom_changed)
	EventBus.tech_unlocked.connect(_on_tech_unlocked)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel_mode"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	queue_free()


func _calculate_graph_size() -> Vector2:
	var max_grid := Vector2i(4, 4)
	for tech in TechDatabase.all():
		max_grid.x = max(max_grid.x, tech.grid_position.x)
		max_grid.y = max(max_grid.y, tech.grid_position.y)
	
	# Compute dynamic bounds to prevent clipping of outlying nodes
	return Vector2(
		float(max_grid.x + 1) * CELL_SIZE.x + 100.0,
		float(max_grid.y + 1) * CELL_SIZE.y + 100.0
	)


func _build_nodes() -> void:
	for tech in TechDatabase.all():
		var node := _make_tech_button(tech)
		_nodes_root.add_child(node)
		_node_buttons[tech.id] = node
	_refresh_nodes()


func _build_inspector_panel() -> void:
	_inspector_panel = PanelContainer.new()
	_inspector_panel.custom_minimum_size = Vector2(320, 0)
	_inspector_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_inspector_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector_panel.add_theme_stylebox_override("panel", _panel_style(COLOR_BG_DETAILS))
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_inspector_panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	_inspector_branch = Label.new()
	_inspector_branch.text = "SELECT SCHEMATIC"
	_inspector_branch.add_theme_font_size_override("font_size", 9)
	_inspector_branch.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(_inspector_branch)
	
	_inspector_title = Label.new()
	_inspector_title.text = "Module Viewer"
	_inspector_title.add_theme_font_size_override("font_size", 16)
	_inspector_title.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	_inspector_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_inspector_title)
	
	vbox.add_child(HSeparator.new())
	
	# Scroll area for descriptions & lists to prevent overflowing
	var scroll_desc := ScrollContainer.new()
	scroll_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_desc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_desc)
	
	var desc_vbox := VBoxContainer.new()
	desc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_vbox.add_theme_constant_override("separation", 12)
	scroll_desc.add_child(desc_vbox)
	
	_inspector_desc = Label.new()
	_inspector_desc.text = "Select an interface module on the network grid to analyze technical pathways, research costs, and database keys."
	_inspector_desc.add_theme_font_size_override("font_size", 11)
	_inspector_desc.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_inspector_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_vbox.add_child(_inspector_desc)
	
	_inspector_cost = Label.new()
	_inspector_cost.text = ""
	_inspector_cost.add_theme_font_size_override("font_size", 12)
	_inspector_cost.add_theme_color_override("font_color", COLOR_WISDOM)
	desc_vbox.add_child(_inspector_cost)
	
	_inspector_unlocks_container = VBoxContainer.new()
	_inspector_unlocks_container.add_theme_constant_override("separation", 4)
	desc_vbox.add_child(_inspector_unlocks_container)
	
	vbox.add_child(HSeparator.new())
	
	_inspector_action_btn = Button.new()
	_inspector_action_btn.text = "SELECT NODE"
	_inspector_action_btn.custom_minimum_size = Vector2(0, 38)
	_inspector_action_btn.add_theme_font_size_override("font_size", 12)
	_inspector_action_btn.disabled = true
	_inspector_action_btn.pressed.connect(_on_inspector_action_pressed)
	vbox.add_child(_inspector_action_btn)


func _update_inspector() -> void:
	if _selected_tech_id == &"":
		_inspector_branch.text = "SYSTEM ACTIVE"
		_inspector_title.text = "Awaiting Input"
		_inspector_desc.text = "Click on any node in the schematic database grid to analyze technical structures and blueprint paths."
		_inspector_cost.text = ""
		_inspector_action_btn.text = "SELECT MODULE"
		_inspector_action_btn.disabled = true
		for child in _inspector_unlocks_container.get_children():
			child.queue_free()
		return
		
	var tech: TechData = TechDatabase.by_id(_selected_tech_id)
	if tech == null:
		return
		
	_inspector_branch.text = "SCHEMATIC COG // " + tech.branch_label.to_upper()
	_inspector_title.text = tech.display_name
	_inspector_desc.text = tech.description
	
	if tech.wisdom_cost > 0:
		_inspector_cost.text = "Required Energy: %d Wisdom Units" % tech.wisdom_cost
	else:
		_inspector_cost.text = "Core Node: Decrypted Base Blueprint"
		
	# Clear previous blueprints list
	for child in _inspector_unlocks_container.get_children():
		child.queue_free()
		
	if tech.unlocked_build_ids.size() > 0:
		var section_title := Label.new()
		section_title.text = "PRINT AUTHORIZATIONS:"
		section_title.add_theme_font_size_override("font_size", 10)
		section_title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_inspector_unlocks_container.add_child(section_title)
		
		for build_id in tech.unlocked_build_ids:
			var item := Label.new()
			item.text = "• Construction ID: %d" % build_id
			item.add_theme_font_size_override("font_size", 11)
			item.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
			_inspector_unlocks_container.add_child(item)
			
	# Match button functionality to the tech's current state
	var state := _state_for(tech.id)
	match state:
		3:
			_inspector_action_btn.text = "MODULE DECRYPTED"
			_inspector_action_btn.disabled = true
		1:
			_inspector_action_btn.text = "INITIATE COGNITIVE LINK"
			_inspector_action_btn.disabled = false
		2:
			_inspector_action_btn.text = "INSUFFICIENT WISDOM"
			_inspector_action_btn.disabled = true
		0:
			_inspector_action_btn.text = "PATHWAY ENCRYPTED"
			_inspector_action_btn.disabled = true


func _make_tech_button(tech: TechData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = NODE_SIZE
	panel.size = NODE_SIZE
	panel.position = _node_origin(tech)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("tech_id", tech.id)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var branch_label := Label.new()
	branch_label.text = tech.branch_label.to_upper()
	branch_label.add_theme_font_size_override("font_size", 9)
	branch_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	box.add_child(branch_label)

	var name_label := Label.new()
	name_label.text = tech.display_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	# Thin tech divider
	var separator := ColorRect.new()
	separator.custom_minimum_size = Vector2(0, 1)
	separator.color = Color(COLOR_TEXT_DIM.r, COLOR_TEXT_DIM.g, COLOR_TEXT_DIM.b, 0.2)
	box.add_child(separator)

	# Bottom detail row containing cost
	var bottom_row := HBoxContainer.new()
	bottom_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(bottom_row)

	var cost_label := Label.new()
	cost_label.text = "%d Wisdom" % tech.wisdom_cost if tech.wisdom_cost > 0 else "Ready"
	cost_label.add_theme_font_size_override("font_size", 10)
	cost_label.add_theme_color_override("font_color", COLOR_WISDOM)
	bottom_row.add_child(cost_label)

	panel.gui_input.connect(_on_node_input.bind(tech.id))
	panel.mouse_entered.connect(_on_node_hover.bind(tech.id, true))
	panel.mouse_exited.connect(_on_node_hover.bind(tech.id, false))
	
	return panel


func _node_origin(tech: TechData) -> Vector2:
	return Vector2(
		40.0 + float(tech.grid_position.x) * CELL_SIZE.x,
		40.0 + float(tech.grid_position.y) * CELL_SIZE.y,
	)


func _node_center(tech: TechData) -> Vector2:
	return _node_origin(tech) + NODE_SIZE * 0.5


func _on_node_hover(tech_id: StringName, hovered: bool) -> void:
	if hovered:
		_hovered_tech_id = tech_id
	else:
		if _hovered_tech_id == tech_id:
			_hovered_tech_id = &""
	_refresh_nodes()


func _on_node_input(event: InputEvent, tech_id: StringName) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_selected_tech_id = tech_id
			_update_inspector()
			_refresh_nodes()
			if mb.double_click:
				_try_unlock(tech_id)


func _on_inspector_action_pressed() -> void:
	if _selected_tech_id != &"":
		_try_unlock(_selected_tech_id)


func _try_unlock(tech_id: StringName) -> void:
	if TechManager == null:
		return
	if TechManager.is_unlocked(tech_id):
		return
	if not TechManager.can_unlock(tech_id):
		if is_instance_valid(AudioManager):
			AudioManager.play_button_press()
		return
		
	if is_instance_valid(AudioManager):
		AudioManager.play_button_press()
	TechManager.try_unlock(tech_id)


func _refresh_nodes() -> void:
	for tech in TechDatabase.all():
		var node: PanelContainer = _node_buttons.get(tech.id) as PanelContainer
		if node == null:
			continue
		var state: int = _state_for(tech.id)
		var is_selected := (tech.id == _selected_tech_id)
		node.add_theme_stylebox_override("panel", _node_style(state, is_selected))
		
	if _graph != null:
		_graph.queue_redraw()


func _state_for(tech_id: StringName) -> int:
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


func _node_style(state: int, is_selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	
	style.set_border_width_all(1)
	style.border_width_left = 5 # Visual indicator band
	
	if is_selected:
		style.border_color = COLOR_ACCENT_AMBER
		style.bg_color = Color(0.06, 0.08, 0.11, 1.0)
	else:
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
	style.border_color = Color(0.18, 0.22, 0.25, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


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
	
	# Draw technical grid overlay in the background
	var grid_step := 60.0
	var grid_color := Color(0.12, 0.16, 0.20, 0.12)
	
	var x_steps := int(_graph.custom_minimum_size.x / grid_step)
	for i in range(x_steps + 1):
		var x := float(i) * grid_step
		_graph.draw_line(Vector2(x, 0), Vector2(x, _graph.custom_minimum_size.y), grid_color, 1.0)
		
	var y_steps := int(_graph.custom_minimum_size.y / grid_step)
	for i in range(y_steps + 1):
		var y := float(i) * grid_step
		_graph.draw_line(Vector2(0, y), Vector2(_graph.custom_minimum_size.x, y), grid_color, 1.0)

	# Draw orthogonal connections with glowing effects
	for tech in TechDatabase.all():
		for prereq_id in tech.prerequisites:
			var prereq: TechData = TechDatabase.by_id(prereq_id)
			if prereq == null:
				continue
			
			var color: Color = COLOR_LINE_LOCKED
			if TechManager != null and TechManager.is_unlocked(prereq.id) and TechManager.is_unlocked(tech.id):
				color = COLOR_LINE_UNLOCKED
			elif TechManager != null and TechManager.is_unlocked(prereq.id):
				color = COLOR_LINE_AVAILABLE
				
			var from_pos: Vector2 = _node_origin(prereq) + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5)
			var to_pos: Vector2 = _node_origin(tech) + Vector2(0.0, NODE_SIZE.y * 0.5)
			
			# Connection highlight checks for selected/hovered traces
			var is_highlighted := false
			if _hovered_tech_id != &"":
				if tech.id == _hovered_tech_id or prereq.id == _hovered_tech_id:
					is_highlighted = true
			if _selected_tech_id != &"":
				if tech.id == _selected_tech_id or prereq.id == _selected_tech_id:
					is_highlighted = true
					
			if is_highlighted:
				# Render glow highlight behind the active trace
				_draw_elbow_connection(from_pos, to_pos, COLOR_ACCENT_AMBER, 3.5)
				_draw_elbow_connection(from_pos, to_pos, Color(1.0, 0.85, 0.6, 1.0), 1.0)
			else:
				# Under-layer line to simulate glowing energy bleed, then sharp core line
				_draw_elbow_connection(from_pos, to_pos, Color(color.r, color.g, color.b, color.a * 0.25), 4.0)
				_draw_elbow_connection(from_pos, to_pos, color, 1.5)


func _draw_elbow_connection(from_pos: Vector2, to_pos: Vector2, color: Color, width: float) -> void:
	var mid_x := (from_pos.x + to_pos.x) * 0.5
	var pt1 := Vector2(mid_x, from_pos.y)
	var pt2 := Vector2(mid_x, to_pos.y)
	
	_graph.draw_line(from_pos, pt1, color, width, true)
	_graph.draw_line(pt1, pt2, color, width, true)
	_graph.draw_line(pt2, to_pos, color, width, true)
	
	# Draw arrow head indicating logic flow direction entering target left boundary
	var arrow_size := 5.0
	var arrow_p1 := to_pos + Vector2(-arrow_size, -arrow_size * 0.8)
	var arrow_p2 := to_pos + Vector2(-arrow_size, arrow_size * 0.8)
	_graph.draw_line(to_pos, arrow_p1, color, width, true)
	_graph.draw_line(to_pos, arrow_p2, color, width, true)


func _on_graph_gui_input(event: InputEvent) -> void:
	# Middle-click or Left-click dragging inside empty space to pan the grid
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_dragging = true
				_drag_start_pos = mb.global_position
				_scroll_start_pos = Vector2(_scroll_container.scroll_horizontal, _scroll_container.scroll_vertical)
			else:
				_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		var delta := mm.global_position - _drag_start_pos
		_scroll_container.scroll_horizontal = int(_scroll_start_pos.x - delta.x)
		_scroll_container.scroll_vertical = int(_scroll_start_pos.y - delta.y)


func _refresh_wisdom_label() -> void:
	if _wisdom_label != null and TechManager != null:
		_wisdom_label.text = "WISDOM BALANCE: %d UNITS" % int(roundf(TechManager.wisdom))


func _on_wisdom_changed(_new_total: float) -> void:
	_refresh_wisdom_label()
	_refresh_nodes()
	_update_inspector()


func _on_tech_unlocked(_tech_id: StringName) -> void:
	_refresh_wisdom_label()
	_refresh_nodes()
	_update_inspector()
