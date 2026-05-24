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

@export var designator_path: NodePath
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath
@export var items_root_path: NodePath
@export var workers_root_path: NodePath

var _designator: Designator
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _items_root: Node2D
var _workers_root: Node2D

var _atlas: Texture2D
var _tab_group: ButtonGroup = ButtonGroup.new()
var _current_tab: StringName = TAB_ORDERS
var _command_grid: GridContainer
var _active_label: Label
var _workers_label: Label
var _jobs_label: Label
var _resource_labels: Dictionary = {}            ## int -> Label
var _command_buttons: Dictionary = {}            ## int -> Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_designator = get_node_or_null(designator_path) as Designator
	_job_board = get_node_or_null(job_board_path) as JobBoard
	_stockpile_manager = get_node_or_null(stockpile_manager_path) as StockpileManager
	_items_root = get_node_or_null(items_root_path) as Node2D
	_workers_root = get_node_or_null(workers_root_path) as Node2D
	_atlas = load(UI_ATLAS_PATH) as Texture2D

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


func _build_layout() -> void:
	var top_strip := PanelContainer.new()
	top_strip.name = "TopStrip"
	top_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	top_strip.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.027, 0.03, 0.90), Color(0.42, 0.45, 0.48, 0.55)))
	top_strip.anchor_left = 0.5
	top_strip.anchor_right = 0.5
	top_strip.offset_left = -430.0
	top_strip.offset_top = 8.0
	top_strip.offset_right = 430.0
	top_strip.offset_bottom = 48.0
	add_child(top_strip)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 10)
	top_margin.add_theme_constant_override("margin_top", 6)
	top_margin.add_theme_constant_override("margin_right", 10)
	top_margin.add_theme_constant_override("margin_bottom", 6)
	top_strip.add_child(top_margin)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 14)
	top_margin.add_child(status_row)

	_workers_label = _status_label("workers 0")
	status_row.add_child(_workers_label)
	_jobs_label = _status_label("jobs 0")
	status_row.add_child(_jobs_label)
	_active_label = _status_label("tool -")
	status_row.add_child(_active_label)
	status_row.add_child(_separator())

	for kind in _tracked_item_kinds():
		var label := _status_label("%s 0" % Item.kind_name(kind))
		label.add_theme_color_override("font_color", Item.kind_color(kind).lerp(Color.WHITE, 0.35))
		status_row.add_child(label)
		_resource_labels[kind] = label

	var palette := PanelContainer.new()
	palette.name = "CommandPalette"
	palette.mouse_filter = Control.MOUSE_FILTER_STOP
	palette.anchors_preset = Control.PRESET_BOTTOM_WIDE
	palette.anchor_left = 0.5
	palette.anchor_top = 1.0
	palette.anchor_right = 0.5
	palette.anchor_bottom = 1.0
	palette.offset_left = -300.0
	palette.offset_top = -210.0
	palette.offset_right = 300.0
	palette.offset_bottom = -10.0
	palette.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.036, 0.04, 0.94), Color(0.56, 0.52, 0.44, 0.65)))
	add_child(palette)

	var palette_margin := MarginContainer.new()
	palette_margin.add_theme_constant_override("margin_left", 10)
	palette_margin.add_theme_constant_override("margin_top", 10)
	palette_margin.add_theme_constant_override("margin_right", 10)
	palette_margin.add_theme_constant_override("margin_bottom", 10)
	palette.add_child(palette_margin)

	var palette_box := VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 8)
	palette_margin.add_child(palette_box)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	palette_box.add_child(tabs)
	_add_tab_button(tabs, TAB_ORDERS, "Orders")
	_add_tab_button(tabs, TAB_ZONES, "Zones")
	_add_tab_button(tabs, TAB_STRUCTURES, "Structures")

	_command_grid = GridContainer.new()
	_command_grid.columns = 4
	_command_grid.add_theme_constant_override("h_separation", 6)
	_command_grid.add_theme_constant_override("v_separation", 6)
	palette_box.add_child(_command_grid)


func _add_tab_button(parent: HBoxContainer, tab: StringName, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = _tab_group
	button.custom_minimum_size = Vector2(112, 30)
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
	_add_command_button(Designator.Mode.NONE, "Cancel", "Clear active tool", ICON_CANCEL)
	_refresh_mode_buttons()


func _commands_for_tab(tab: StringName) -> Array[Dictionary]:
	match tab:
		TAB_ZONES:
			return [
				{"mode": Designator.Mode.STOCKPILE, "label": "Stockpile", "tooltip": "Paint stockpile zone", "icon": ICON_STOCKPILE},
				{"mode": Designator.Mode.REMOVE_STOCKPILE, "label": "Remove", "tooltip": "Remove stockpile zone", "icon": ICON_REMOVE},
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
			]
		_:
			return [
				{"mode": Designator.Mode.MINE, "label": "Mine", "tooltip": "Mark wall cells for mining", "icon": ICON_MINE},
			]


func _add_command_button(mode: int, label: String, tooltip: String, icon_cell: Vector2i) -> void:
	var button := Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(112, 56)
	button.icon = _atlas_icon(icon_cell)
	button.expand_icon = true
	button.add_theme_stylebox_override("normal", _button_style(Color(0.070, 0.074, 0.082, 0.96)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.115, 0.122, 0.132, 0.98)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.34, 0.29, 0.18, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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


func _on_workers_selected(_workers: Array[Worker]) -> void:
	_refresh_status()


func _refresh_all() -> void:
	_refresh_mode_buttons()
	_refresh_status()


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
	var parts: Array[String] = []
	var ingredients: Dictionary = BuildBlueprint.ingredients(blueprint_id)
	for kind in ingredients.keys():
		parts.append("%s x%d" % [Item.kind_name(int(kind)), int(ingredients[kind])])
	return "%s: %s" % [BuildBlueprint.display_name(blueprint_id).capitalize(), ", ".join(parts)]


func _atlas_icon(cell: Vector2i) -> Texture2D:
	if _atlas == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = _atlas
	icon.region = Rect2(Vector2(cell * ICON_CELL_SIZE), Vector2(ICON_CELL_SIZE))
	return icon


func _status_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.90, 1.0))
	return label


func _separator() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(8, 0)
	return sep


func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _button_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(0.30, 0.31, 0.32, 0.8)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	return style
