class_name ColonyHud
extends Control
##
## RimWorld-style colony HUD foundation: compact status strip plus grouped
## command palette. Buttons drive Designator; keyboard shortcuts remain
## secondary access paths.
##

const UI_ATLAS_PATH := "res://resources/ui/placeholder_ui_atlas.png"
const ICON_CELL_SIZE := Vector2i(32, 32)

const TAB_ORDERS := &"orders"
const TAB_ZONES := &"zones"
const TAB_STRUCTURES := &"structures"
const TAB_ROOMS := &"rooms"

const ICON_CANCEL := Vector2i(0, 0)
const ICON_MINE := Vector2i(1, 0)
const ICON_STOCKPILE := Vector2i(2, 0)
const ICON_REMOVE := Vector2i(3, 0)
const ICON_WALL := Vector2i(4, 0)
const ICON_DOOR := Vector2i(5, 0)
const ICON_LIGHT := Vector2i(6, 0)
const ICON_EXTRACTOR := Vector2i(7, 0)
const ICON_SENSOR := Vector2i(8, 0)
const ICON_CHARGE_PAD := Vector2i(9, 0)
const ICON_FABRICATOR := Vector2i(10, 0)
const ICON_DOCK := ICON_CHARGE_PAD
const ICON_REPAIR_BENCH := ICON_FABRICATOR
const ICON_PARTS_LOOM := ICON_FABRICATOR
const ICON_MAINTENANCE_DOCK := ICON_CHARGE_PAD
const ICON_CALIBRATION_SHRINE := ICON_SENSOR

# Colors for UI accents and states
const COLOR_BG_DARK := Color(0.055, 0.072, 0.088, 0.94)
const COLOR_BG_RAISED := Color(0.10, 0.125, 0.145, 0.96)
const COLOR_BORDER_DEFAULT := Color(0.22, 0.48, 0.55, 0.55)
const COLOR_ACCENT_AMBER := Color(0.96, 0.58, 0.16, 1.0)
const COLOR_ACCENT_CYAN := Color(0.42, 0.85, 0.92, 1.0)
const COLOR_ACCENT_MUTED := Color(0.40, 0.52, 0.58, 0.55)
const COLOR_TEXT_LIGHT := Color(0.92, 0.96, 0.97, 1.0)
const COLOR_TEXT_MUTED := Color(0.68, 0.75, 0.78, 1.0)
const COLOR_METER_GOOD := Color(0.3, 0.9, 0.55)
const COLOR_METER_LOW := Color(1.0, 0.78, 0.2)
const COLOR_FACTION_HOSTILE := Color(0.96, 0.36, 0.34, 1.0)
const COLOR_FACTION_NEUTRAL := Color(0.97, 0.78, 0.32, 1.0)
const HISTORY_VISIBLE_ROWS: int = 4
const ENTITY_ATLAS_PATH := "res://resources/entities/placeholder_entities_atlas.png"
const BOT_REGION := Rect2(Vector2.ZERO, Vector2(16, 16))
const NEUTRAL_REGION := Rect2(Vector2(16, 0), Vector2(16, 16))
const PALETTE_WIDTH: float = 580.0
const PALETTE_HEIGHT: float = 200.0
const TOP_STRIP_HEIGHT: float = 44.0
const INSPECT_CARD_WIDTH: float = 300.0
const INSPECT_CARD_HEIGHT: float = 150.0

@export var designator_path: NodePath
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath
@export var items_root_path: NodePath
@export var workers_root_path: NodePath
@export var structure_manager_path: NodePath
@export var camera_path: NodePath

var _designator: Designator
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _items_root: Node2D
var _workers_root: Node2D
var _structure_manager: StructureManager
var _camera: CameraController

var _atlas: Texture2D
var _entity_atlas: Texture2D
var _tab_group: ButtonGroup = ButtonGroup.new()
var _current_tab: StringName = TAB_ORDERS
var _command_grid: GridContainer
var _active_label: Label
var _workers_label: Label
var _jobs_label: Label
var _resource_labels: Dictionary = {}            ## int -> Label
var _command_buttons: Dictionary = {}            ## int -> Button
var _selection_panel: PanelContainer
var _selection_box: HBoxContainer
var _npc_strip: BoxContainer
var _selected_workers: Array[Worker] = []
var _selected_structure_id: int = -1
var _selected_structure_anchor: Vector2i = Vector2i.ZERO
var _top_strip: PanelContainer
var _inspect_panel: PanelContainer
var _inspect_box: VBoxContainer
var _inspected_node: Node = null
var _inspected_faction: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_designator = get_node_or_null(designator_path) as Designator
	_job_board = get_node_or_null(job_board_path) as JobBoard
	_stockpile_manager = get_node_or_null(stockpile_manager_path) as StockpileManager
	_items_root = get_node_or_null(items_root_path) as Node2D
	_workers_root = get_node_or_null(workers_root_path) as Node2D
	_structure_manager = get_node_or_null(structure_manager_path) as StructureManager
	_camera = get_node_or_null(camera_path) as CameraController
	_atlas = load(UI_ATLAS_PATH) as Texture2D
	_entity_atlas = load(ENTITY_ATLAS_PATH) as Texture2D

	_build_layout()
	_connect_signals()
	_set_tab(TAB_ORDERS)
	_refresh_all()

	var refresh_timer := Timer.new()
	refresh_timer.wait_time = 0.5
	refresh_timer.timeout.connect(_refresh_status)
	add_child(refresh_timer)
	refresh_timer.start()


func _connect_signals() -> void:
	if _designator != null:
		_designator.mode_changed.connect(_on_mode_changed)
	if _job_board != null:
		_job_board.job_added.connect(_on_job_changed)
		_job_board.job_completed.connect(_on_job_changed)
		_job_board.job_cancelled.connect(_on_job_changed)
	if _stockpile_manager != null:
		_stockpile_manager.stockpile_changed.connect(_refresh_status)
	EventBus.workers_selected.connect(_on_workers_selected)
	EventBus.structure_selected.connect(_on_structure_selected)
	EventBus.bot_inspected.connect(_on_bot_inspected)
	EventBus.combatant_died.connect(_on_combatant_died)


func _build_layout() -> void:
	# Top Strip Container - centered horizontally, auto-sizes to badges.
	var top_strip := PanelContainer.new()
	top_strip.name = "TopStrip"
	top_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	top_strip.add_theme_stylebox_override("panel", _panel_style(COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 6.0, true))
	top_strip.anchor_left = 0.5
	top_strip.anchor_right = 0.5
	top_strip.anchor_top = 0.0
	top_strip.anchor_bottom = 0.0
	top_strip.offset_top = 10.0
	top_strip.offset_bottom = 10.0 + TOP_STRIP_HEIGHT
	top_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_top_strip = top_strip
	add_child(top_strip)
	top_strip.resized.connect(_recenter_top_strip)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 10)
	top_margin.add_theme_constant_override("margin_top", 5)
	top_margin.add_theme_constant_override("margin_right", 10)
	top_margin.add_theme_constant_override("margin_bottom", 5)
	top_strip.add_child(top_margin)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 7)
	top_margin.add_child(status_row)

	# Stats Badges
	_workers_label = _status_label("workers 0")
	status_row.add_child(_badge_container(_workers_label))

	_jobs_label = _status_label("jobs 0")
	status_row.add_child(_badge_container(_jobs_label))

	_active_label = _status_label("tool -")
	_active_label.add_theme_color_override("font_color", COLOR_ACCENT_AMBER)
	status_row.add_child(_badge_container(_active_label))

	status_row.add_child(_separator())

	# Resource Badges
	for kind in _tracked_item_kinds():
		var label := _status_label("%s 0" % Item.kind_name(kind))
		label.add_theme_color_override("font_color", Item.kind_color(kind).lerp(Color.WHITE, 0.4))

		var badge := _badge_container(label)
		status_row.add_child(badge)
		_resource_labels[kind] = label

	var npc_panel := PanelContainer.new()
	npc_panel.name = "NpcStrip"
	npc_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	npc_panel.anchor_left = 0.0
	npc_panel.anchor_top = 0.0
	npc_panel.anchor_right = 0.0
	npc_panel.anchor_bottom = 0.0
	npc_panel.offset_left = 12.0
	npc_panel.offset_top = 70.0
	npc_panel.offset_right = 204.0
	npc_panel.offset_bottom = 208.0
	npc_panel.add_theme_stylebox_override("panel", _panel_style(COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 6.0, true))
	add_child(npc_panel)

	var npc_margin := MarginContainer.new()
	npc_margin.add_theme_constant_override("margin_left", 7)
	npc_margin.add_theme_constant_override("margin_top", 7)
	npc_margin.add_theme_constant_override("margin_right", 7)
	npc_margin.add_theme_constant_override("margin_bottom", 7)
	npc_panel.add_child(npc_margin)

	var npc_scroll := ScrollContainer.new()
	npc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	npc_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	npc_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_margin.add_child(npc_scroll)

	_npc_strip = VBoxContainer.new()
	_npc_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_strip.add_theme_constant_override("separation", 6)
	npc_scroll.add_child(_npc_strip)

	# Command Palette Panel - centered horizontally at bottom.
	var palette := PanelContainer.new()
	palette.name = "CommandPalette"
	palette.mouse_filter = Control.MOUSE_FILTER_STOP
	palette.anchor_left = 0.5
	palette.anchor_top = 1.0
	palette.anchor_right = 0.5
	palette.anchor_bottom = 1.0
	palette.offset_left = -PALETTE_WIDTH * 0.5
	palette.offset_top = -PALETTE_HEIGHT - 16.0
	palette.offset_right = PALETTE_WIDTH * 0.5
	palette.offset_bottom = -16.0
	palette.add_theme_stylebox_override("panel", _panel_style(COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 6.0, true))
	add_child(palette)

	var palette_margin := MarginContainer.new()
	palette_margin.add_theme_constant_override("margin_left", 10)
	palette_margin.add_theme_constant_override("margin_top", 9)
	palette_margin.add_theme_constant_override("margin_right", 10)
	palette_margin.add_theme_constant_override("margin_bottom", 10)
	palette.add_child(palette_margin)

	var palette_box := VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 8)
	palette_margin.add_child(palette_box)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	palette_box.add_child(tabs)

	_add_tab_button(tabs, TAB_ORDERS, "Orders")
	_add_tab_button(tabs, TAB_ZONES, "Zones")
	_add_tab_button(tabs, TAB_ROOMS, "Rooms")
	_add_tab_button(tabs, TAB_STRUCTURES, "Structures")

	_command_grid = GridContainer.new()
	_command_grid.columns = 5
	_command_grid.add_theme_constant_override("h_separation", 6)
	_command_grid.add_theme_constant_override("v_separation", 7)
	palette_box.add_child(_command_grid)

	_selection_panel = PanelContainer.new()
	_selection_panel.name = "SelectionPanel"
	_selection_panel.visible = false
	_selection_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_selection_panel.anchor_left = 1.0
	_selection_panel.anchor_top = 1.0
	_selection_panel.anchor_right = 1.0
	_selection_panel.anchor_bottom = 1.0
	_selection_panel.offset_left = -670.0
	_selection_panel.offset_top = -282.0
	_selection_panel.offset_right = -16.0
	_selection_panel.offset_bottom = -16.0
	_selection_panel.add_theme_stylebox_override("panel", _panel_style(COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 5.0, true))
	add_child(_selection_panel)

	var selection_margin := MarginContainer.new()
	selection_margin.add_theme_constant_override("margin_left", 12)
	selection_margin.add_theme_constant_override("margin_top", 12)
	selection_margin.add_theme_constant_override("margin_right", 12)
	selection_margin.add_theme_constant_override("margin_bottom", 12)
	_selection_panel.add_child(selection_margin)

	var selection_scroll := ScrollContainer.new()
	selection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	selection_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	selection_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selection_margin.add_child(selection_scroll)

	_selection_box = HBoxContainer.new()
	_selection_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_selection_box.add_theme_constant_override("separation", 10)
	selection_scroll.add_child(_selection_box)

	# NPC Inspect Card - centered above the command palette.
	_inspect_panel = PanelContainer.new()
	_inspect_panel.name = "InspectCard"
	_inspect_panel.visible = false
	_inspect_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspect_panel.anchor_left = 0.5
	_inspect_panel.anchor_top = 1.0
	_inspect_panel.anchor_right = 0.5
	_inspect_panel.anchor_bottom = 1.0
	_inspect_panel.offset_left = -INSPECT_CARD_WIDTH * 0.5
	_inspect_panel.offset_top = -PALETTE_HEIGHT - 16.0 - INSPECT_CARD_HEIGHT - 10.0
	_inspect_panel.offset_right = INSPECT_CARD_WIDTH * 0.5
	_inspect_panel.offset_bottom = -PALETTE_HEIGHT - 16.0 - 10.0
	_inspect_panel.add_theme_stylebox_override("panel", _panel_style(COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 6.0, true))
	add_child(_inspect_panel)

	var inspect_margin := MarginContainer.new()
	inspect_margin.add_theme_constant_override("margin_left", 12)
	inspect_margin.add_theme_constant_override("margin_top", 10)
	inspect_margin.add_theme_constant_override("margin_right", 12)
	inspect_margin.add_theme_constant_override("margin_bottom", 10)
	_inspect_panel.add_child(inspect_margin)

	_inspect_box = VBoxContainer.new()
	_inspect_box.add_theme_constant_override("separation", 4)
	inspect_margin.add_child(_inspect_box)

	_recenter_top_strip()


func _recenter_top_strip() -> void:
	if _top_strip == null:
		return
	var w: float = _top_strip.size.x
	if w <= 0.0:
		w = _top_strip.get_combined_minimum_size().x
	if w <= 0.0:
		return
	_top_strip.offset_left = -w * 0.5
	_top_strip.offset_right = w * 0.5


func _add_tab_button(parent: HBoxContainer, tab: StringName, label_text: String) -> void:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.button_group = _tab_group
	button.custom_minimum_size = Vector2(96, 28)
	button.add_theme_font_size_override("font_size", 12)

	# Tab specific styling
	button.add_theme_stylebox_override("normal", _tab_style(Color(0.12, 0.14, 0.16, 0.4), Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", _tab_style(Color(0.18, 0.20, 0.22, 0.6), COLOR_ACCENT_MUTED))
	button.add_theme_stylebox_override("pressed", _tab_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_AMBER))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	button.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

	button.pressed.connect(_set_tab.bind(tab))
	parent.add_child(button)


func _set_tab(tab: StringName) -> void:
	_current_tab = tab
	for child in _command_grid.get_children():
		_command_grid.remove_child(child)
		child.queue_free()
	_command_buttons.clear()

	for command in _commands_for_tab(tab):
		_add_command_button(
			int(command["mode"]),
			command["label"] as String,
			command["tooltip"] as String,
			command["icon"] as Vector2i,
		)
	_refresh_mode_buttons()


func _commands_for_tab(tab: StringName) -> Array[Dictionary]:
	match tab:
		TAB_ZONES:
			return [
				{"mode": Designator.Mode.STOCKPILE, "label": "Stockpile", "tooltip": "Stockpile\nPaint explored walkable cells for loose item storage.\nWorkers haul loose stacks here and merge same-kind stacks.", "icon": ICON_STOCKPILE},
				{"mode": Designator.Mode.REMOVE_STOCKPILE, "label": "Remove", "tooltip": "Remove stockpile\nDeletes stockpile zone under cursor.\nStored items drop in place as loose stacks.", "icon": ICON_REMOVE},
			]
		TAB_ROOMS:
			return [
				{"mode": Designator.Mode.DESIGNATE_DOCK_ROOM, "label": "Dock Room", "tooltip": "Dock Room\nPersonal space for a bot to rest.\nMinimum 1x2 with a Dock (bed). One bot per room.\nMissing rooms tank mood over time.", "icon": ICON_DOCK},
				{"mode": Designator.Mode.REMOVE_ROOM, "label": "Remove", "tooltip": "Remove room\nDeletes the room designation under cursor.\nAssigned bot loses its dock room need satisfier.", "icon": ICON_REMOVE},
			]
		TAB_STRUCTURES:
			return [
				{"mode": Designator.Mode.BUILD_WALL, "label": "Wall", "tooltip": _build_tooltip(BuildBlueprint.Id.WALL), "icon": ICON_WALL},
				{"mode": Designator.Mode.BUILD_DOOR, "label": "Door", "tooltip": _build_tooltip(BuildBlueprint.Id.DOOR), "icon": ICON_DOOR},
				{"mode": Designator.Mode.BUILD_LIGHT, "label": "Light", "tooltip": _build_tooltip(BuildBlueprint.Id.LIGHT), "icon": ICON_LIGHT},
				{"mode": Designator.Mode.BUILD_EXTRACTOR, "label": "Extractor", "tooltip": _build_tooltip(BuildBlueprint.Id.EXTRACTOR), "icon": ICON_EXTRACTOR},
				{"mode": Designator.Mode.BUILD_SENSOR, "label": "Sensor", "tooltip": _build_tooltip(BuildBlueprint.Id.SENSOR), "icon": ICON_SENSOR},
				{"mode": Designator.Mode.BUILD_CHARGE_PAD, "label": "Charge", "tooltip": _build_tooltip(BuildBlueprint.Id.CHARGE_PAD), "icon": ICON_CHARGE_PAD},
				{"mode": Designator.Mode.BUILD_FABRICATOR, "label": "Fabricator", "tooltip": _build_tooltip(BuildBlueprint.Id.FABRICATOR), "icon": ICON_FABRICATOR},
				{"mode": Designator.Mode.BUILD_DOCK, "label": "Dock", "tooltip": _build_tooltip(BuildBlueprint.Id.DOCK), "icon": ICON_DOCK},
				{"mode": Designator.Mode.BUILD_REPAIR_BENCH, "label": "Repair", "tooltip": _build_tooltip(BuildBlueprint.Id.REPAIR_BENCH), "icon": ICON_REPAIR_BENCH},
				{"mode": Designator.Mode.BUILD_PARTS_LOOM, "label": "Parts Loom", "tooltip": _build_tooltip(BuildBlueprint.Id.PARTS_LOOM), "icon": ICON_PARTS_LOOM},
				{"mode": Designator.Mode.BUILD_MAINTENANCE_DOCK, "label": "Maint Dock", "tooltip": _build_tooltip(BuildBlueprint.Id.MAINTENANCE_DOCK), "icon": ICON_MAINTENANCE_DOCK},
				{"mode": Designator.Mode.BUILD_CALIBRATION_SHRINE, "label": "Calibrate", "tooltip": _build_tooltip(BuildBlueprint.Id.CALIBRATION_SHRINE), "icon": ICON_CALIBRATION_SHRINE},
			]
		_:
			return [
				{"mode": Designator.Mode.MINE, "label": "Mine", "tooltip": "Mine\nMark wall, service core, or rich wall cells.\nWorkers dig adjacent cells and drop salvage resources.", "icon": ICON_MINE},
			]


func _add_command_button(mode: int, label_text: String, tooltip: String, icon_cell: Vector2i) -> void:
	var button := Button.new()
	button.text = label_text
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(96, 38)
	button.icon = _atlas_icon(icon_cell)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Styling typography & spacing for button structure
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_constant_override("h_separation", 6)

	var base_button_color := COLOR_BG_RAISED
	var hover_button_color := Color(0.16, 0.18, 0.20, 0.95)
	var active_button_color := Color(0.25, 0.20, 0.12, 1.0) # Amber tone when active

	button.add_theme_stylebox_override("normal", _button_style(base_button_color, COLOR_BORDER_DEFAULT))
	button.add_theme_stylebox_override("hover", _button_style(hover_button_color, COLOR_ACCENT_MUTED))
	button.add_theme_stylebox_override("pressed", _button_style(active_button_color, COLOR_ACCENT_AMBER))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	button.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

	button.pressed.connect(_on_command_pressed.bind(mode))
	_command_grid.add_child(button)
	_command_buttons[mode] = button


func _on_command_pressed(mode: int) -> void:
	if _designator == null:
		return
	if mode == Designator.Mode.NONE:
		_designator.set_mode(Designator.Mode.NONE)
	else:
		_designator.toggle_mode(mode)


func _on_mode_changed(_mode: int) -> void:
	_refresh_mode_buttons()
	_refresh_status()


func _on_job_changed(_job: Job) -> void:
	_refresh_status()


func _on_workers_selected(workers: Array[Worker]) -> void:
	_selected_workers = workers
	if not _selected_workers.is_empty():
		_selected_structure_id = -1
		_inspected_node = null
		_inspected_faction = 0
	_refresh_status()
	_refresh_selection_panel()
	_refresh_inspect_card()


func _on_structure_selected(id: int, anchor: Vector2i) -> void:
	_selected_structure_id = id
	_selected_structure_anchor = anchor
	if id >= 0:
		_selected_workers.clear()
		_inspected_node = null
		_inspected_faction = 0
	_refresh_selection_panel()
	_refresh_inspect_card()


func _on_bot_inspected(node: Node, faction: int) -> void:
	_inspected_node = node
	_inspected_faction = faction
	if node != null:
		_selected_workers.clear()
		_selected_structure_id = -1
		_refresh_selection_panel()
	_refresh_inspect_card()


func _on_combatant_died(node: Node, _faction: int) -> void:
	if node == _inspected_node:
		_inspected_node = null
		_refresh_inspect_card()


func _refresh_all() -> void:
	_refresh_mode_buttons()
	_refresh_status()
	_refresh_selection_panel()


func _refresh_mode_buttons() -> void:
	var active: int = _designator.current_mode() if _designator != null else Designator.Mode.NONE
	for key in _command_buttons.keys():
		var button := _command_buttons[key] as Button
		if button == null:
			continue
		button.set_pressed_no_signal(int(key) == active)


func _refresh_status() -> void:
	var worker_count: int = _workers_root.get_child_count() if _workers_root != null else 0
	var job_count: int = _job_board.pending_count() if _job_board != null else 0
	_workers_label.text = "workers %d" % worker_count
	_jobs_label.text = "jobs %d" % job_count
	_active_label.text = "tool %s" % (_designator.mode_label().to_lower() if _designator != null else "-")

	var counts: Dictionary = _resource_counts()
	for kind in _resource_labels.keys():
		var label := _resource_labels[kind] as Label
		if label != null:
			label.text = "%s %d" % [Item.kind_name(int(kind)), int(counts.get(kind, 0))]
	_refresh_npc_strip()
	_refresh_selection_panel()
	_refresh_inspect_card()


func _resource_counts() -> Dictionary:
	var counts: Dictionary = {
		Item.Kind.SCRAP: 0,
		Item.Kind.COMPONENT: 0,
		Item.Kind.SUBSTRATE: 0,
		Item.Kind.CIRCUIT: 0,
		Item.Kind.POWER_CELL: 0,
	}
	if _items_root != null:
		for child in _items_root.get_children():
			var item := child as Item
			if item != null:
				counts[item.kind] = int(counts.get(item.kind, 0)) + item.count
	if _stockpile_manager != null:
		for zone in _stockpile_manager.zones:
			for value in zone.occupant.values():
				var item: Item = null
				if value is Item:
					item = value as Item
				elif value is Dictionary:
					item = (value as Dictionary).get(StockpileZone.R_EXISTING) as Item
				if item != null and is_instance_valid(item):
					counts[item.kind] = int(counts.get(item.kind, 0)) + item.count
	return counts


func _tracked_item_kinds() -> Array[int]:
	return [
		Item.Kind.SCRAP,
		Item.Kind.COMPONENT,
		Item.Kind.SUBSTRATE,
		Item.Kind.CIRCUIT,
		Item.Kind.POWER_CELL,
	]


func _build_tooltip(blueprint_id: int) -> String:
	return BuildBlueprint.tooltip_text(blueprint_id)


func _refresh_inspect_card() -> void:
	if _inspect_panel == null or _inspect_box == null:
		return
	for child in _inspect_box.get_children():
		_inspect_box.remove_child(child)
		child.queue_free()
	if _inspected_node == null or not is_instance_valid(_inspected_node):
		_inspect_panel.visible = false
		return
	_inspect_panel.visible = true
	var faction_color: Color = COLOR_FACTION_NEUTRAL if _inspected_faction == 1 else COLOR_FACTION_HOSTILE
	var faction_text: String = "neutral" if _inspected_faction == 1 else "hostile"

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	_inspect_box.add_child(title_row)

	var portrait := TextureRect.new()
	portrait.texture = _npc_portrait()
	portrait.modulate = faction_color if _inspected_faction == 2 else Color.WHITE
	portrait.custom_minimum_size = Vector2(24, 24)
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_row.add_child(portrait)

	var name_label := Label.new()
	name_label.text = _inspected_node.call("display_name") as String if _inspected_node.has_method("display_name") else str(_inspected_node.name)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_label)

	var faction_label := Label.new()
	faction_label.text = faction_text
	faction_label.add_theme_font_size_override("font_size", 12)
	faction_label.add_theme_color_override("font_color", faction_color)
	title_row.add_child(faction_label)

	var stats_value: CombatStats = _inspected_node.call("combat_stats") as CombatStats if _inspected_node.has_method("combat_stats") else null
	if stats_value != null:
		_add_meter(_inspect_box, "hp %d / %d" % [int(roundf(stats_value.hp)), int(roundf(stats_value.max_hp))], stats_value.hp_ratio(), Color(0.95, 0.30, 0.30))
		_add_card_line(_inspect_box, "damage", "%d-%d" % [int(stats_value.damage_min), int(stats_value.damage_max)])

	if _inspected_node.has_method("state_label"):
		_add_card_line(_inspect_box, "state", _inspected_node.call("state_label") as String)
	if _inspected_node.has_method("current_target"):
		var target_node: Node = _inspected_node.call("current_target") as Node
		if target_node != null and is_instance_valid(target_node):
			var target_name: String = target_node.call("display_name") as String if target_node.has_method("display_name") else str(target_node.name)
			_add_card_line(_inspect_box, "target", target_name)


func _npc_portrait() -> Texture2D:
	if _entity_atlas == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = _entity_atlas
	icon.region = NEUTRAL_REGION
	return icon


func _refresh_selection_panel() -> void:
	if _selection_panel == null or _selection_box == null:
		return
	for child in _selection_box.get_children():
		_selection_box.remove_child(child)
		child.queue_free()
	if _selected_structure_id >= 0:
		_build_structure_card()
	elif not _selected_workers.is_empty():
		_build_worker_cards()
	_selection_panel.visible = _selection_box.get_child_count() > 0


func _build_worker_cards() -> void:
	var live_workers: Array[Worker] = []
	for worker in _selected_workers:
		if worker != null and is_instance_valid(worker):
			live_workers.append(worker)
	_selected_workers = live_workers
	var shown: int = mini(live_workers.size(), 3)
	for i in range(shown):
		var worker: Worker = live_workers[i]
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(196, 0)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.add_theme_constant_override("separation", 3)
		_selection_box.add_child(card)
		_add_card_title(card, worker.display_name())
		_add_card_line(card, "state", worker.state_label())
		_add_card_line(card, "job", worker.job_label())
		_add_card_line(card, "carry", worker.carried_label())
		_add_meter(card, "energy", worker.energy_ratio(), COLOR_METER_LOW if worker.energy_ratio() < 0.3 else COLOR_METER_GOOD)
		_add_meter(card, "condition", worker.condition_ratio(), Color(0.95, 0.52, 0.38))
		_add_meter(card, "mental tired", worker.mental_tiredness_ratio(), Color(0.72, 0.58, 1.0))
		_add_meter(card, "social", worker.social_ratio(), Color(0.55, 0.85, 0.55))
		var mood_color: Color = Color(0.96, 0.5, 0.32) if worker.mood_ratio() < 0.4 else Color(0.95, 0.85, 0.4)
		_add_meter(card, "mood (%s)" % worker.mood_label(), worker.mood_ratio(), mood_color)
		var needs: Array[String] = worker.unsatisfied_needs()
		if needs.is_empty():
			_add_card_line(card, "needs", "satisfied", COLOR_METER_GOOD)
		else:
			_add_card_line(card, "needs", ", ".join(needs), Color(1.0, 0.5, 0.35))
		for limb_line in worker.limb_status_lines():
			_add_card_line(card, "limb", limb_line)
		_add_history_panel(card, worker)
	if live_workers.size() > 3:
		_add_card_line(_selection_box, "more", "%d selected" % live_workers.size())


func _build_structure_card() -> void:
	if _structure_manager == null:
		return
	var status: Dictionary = _structure_manager.structure_status_by_anchor(_selected_structure_anchor)
	if status.is_empty():
		_selected_structure_id = -1
		return
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(360, 0)
	card.add_theme_constant_override("separation", 4)
	_selection_box.add_child(card)
	_add_card_title(card, (status["name"] as String).capitalize())
	_add_card_line(card, "grid", "%d,%d" % [_selected_structure_anchor.x, _selected_structure_anchor.y])
	_add_card_line(card, "does", status["description"] as String)
	_add_card_line(card, "production", status["production"] as String)
	var interval: float = float(status["interval"])
	if interval > 0.0:
		_add_meter(card, "progress", float(status["progress"]), COLOR_ACCENT_AMBER)
		_add_card_line(card, "cycle", "%.0fs" % interval)
	var inputs: String = status["inputs"] as String
	if inputs != "none":
		_add_card_line(card, "inputs", inputs)
	var blocked: String = status["blocked"] as String
	if not blocked.is_empty():
		_add_card_line(card, "blocked", blocked, Color(1.0, 0.5, 0.35))


func _add_card_title(parent: Control, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(label)


func _add_card_line(parent: Control, key: String, value: String, color: Color = COLOR_TEXT_LIGHT) -> void:
	var label := Label.new()
	label.text = "%s: %s" % [key, value]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _add_meter(parent: Control, label_text: String, ratio: float, fill: Color) -> void:
	var label := Label.new()
	label.text = "%s %d%%" % [label_text, int(roundf(clampf(ratio, 0.0, 1.0) * 100.0))]
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	parent.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.10, 0.95)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.corner_radius_top_left = 2
	fg.corner_radius_top_right = 2
	fg.corner_radius_bottom_left = 2
	fg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	parent.add_child(bar)


func _add_history_panel(parent: Control, worker: Worker) -> void:
	var title := Label.new()
	title.text = "thought history"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	parent.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(178, HISTORY_VISIBLE_ROWS * 16)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(178, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)

	var history: Array[String] = worker.action_history()
	for entry in history:
		var label := Label.new()
		label.text = entry
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(168, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
		box.add_child(label)


func _refresh_npc_strip() -> void:
	if _npc_strip == null:
		return
	for child in _npc_strip.get_children():
		_npc_strip.remove_child(child)
		child.queue_free()
	if _workers_root == null:
		return
	for child in _workers_root.get_children():
		var worker := child as Worker
		if worker == null:
			continue
		var button := Button.new()
		button.text = worker.display_name()
		button.icon = _bot_icon()
		button.expand_icon = true
		button.custom_minimum_size = Vector2(176, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_stylebox_override("normal", _button_style(COLOR_BG_RAISED, COLOR_BORDER_DEFAULT))
		button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.20, 0.16, 0.10, 1.0), COLOR_ACCENT_AMBER))
		button.pressed.connect(_focus_worker.bind(worker))
		_npc_strip.add_child(button)


func _focus_worker(worker: Worker) -> void:
	if worker == null or not is_instance_valid(worker) or _camera == null:
		return
	_camera.center_on(worker.global_position)


func _bot_icon() -> Texture2D:
	if _entity_atlas == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = _entity_atlas
	icon.region = BOT_REGION
	return icon


func _atlas_icon(cell: Vector2i) -> Texture2D:
	if _atlas == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = _atlas
	icon.region = Rect2(Vector2(cell * ICON_CELL_SIZE), Vector2(ICON_CELL_SIZE))
	return icon


func _status_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	return label


# Wraps a label in a neat panel "badge" for consistent visual separation
func _badge_container(content_label: Label) -> PanelContainer:
	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = COLOR_BG_RAISED
	badge_style.set_border_width_all(1)
	badge_style.border_color = Color(0.29, 0.32, 0.35, 0.46)
	badge_style.corner_radius_top_left = 3
	badge_style.corner_radius_top_right = 3
	badge_style.corner_radius_bottom_left = 3
	badge_style.corner_radius_bottom_right = 3
	badge.add_theme_stylebox_override("panel", badge_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 3)

	badge.add_child(margin)
	margin.add_child(content_label)
	return badge


func _separator() -> Control:
	var sep := VSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = COLOR_ACCENT_MUTED
	sep_style.vertical = true
	sep_style.grow_begin = 2.0
	sep_style.grow_end = 2.0
	sep.add_theme_stylebox_override("line", sep_style)
	sep.custom_minimum_size = Vector2(12, 0)
	return sep


func _panel_style(fill: Color, border: Color, radius: float, with_shadow: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)

	if with_shadow:
		style.shadow_color = Color(0, 0, 0, 0.38)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 4)
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 9.0
	style.content_margin_right = 8.0
	return style


func _tab_style(fill: Color, bottom_border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4

	# Tab style uses a dynamic accent line on the bottom edge to show focus/selection
	if bottom_border_color != Color.TRANSPARENT:
		style.set_border_width_all(0)
		style.border_width_bottom = 2
		style.border_color = bottom_border_color

	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style
