class_name ColonyHud
extends Control
##
## RimWorld-style colony HUD foundation: compact status strip plus grouped
## command palette. Buttons drive Designator; keyboard shortcuts remain
## secondary access paths.
##

const UI_ATLAS_PATH := "res://resources/ui/placeholder_ui_atlas.png"
const WORKSHOP_ATLAS_PATH := "res://resources/objects/workshops_atlas.png"
const OBJECT_ATLAS_PATH := "res://resources/objects/craftable_objects_atlas.png"
const DOOR_ATLAS_PATH := "res://resources/objects/doors_atlas.png"
const ICON_CELL_SIZE := Vector2i(32, 32)
const WORKSHOP_ICON_SOURCE_SIZE := Vector2i(64, 64)

const TAB_ORDERS := &"orders"
const TAB_ZONES := &"zones"
const TAB_ROOMS := &"rooms"
const TAB_WORKSHOPS := &"workshops"
const TAB_BUILDING := &"building"
# Subtabs nested under Building — they don't get top-level tab buttons.
const TAB_BUILD_GENERAL := &"build_general"
const TAB_STORAGE := &"storage"
const TAB_VISIBILITY := &"visibility"
const TAB_OBJECTS := &"objects"
const BUILDING_SUBTABS: Array[StringName] = [
	TAB_BUILD_GENERAL, TAB_STORAGE, TAB_VISIBILITY, TAB_OBJECTS,
]
const BUILDING_SUBTAB_LABELS: Dictionary = {
	TAB_BUILD_GENERAL: "General",
	TAB_STORAGE: "Storage",
	TAB_VISIBILITY: "Visibility",
	TAB_OBJECTS: "Objects",
}

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
const ICON_MEDITATION_PAD := ICON_SENSOR
const ICON_SENTIENCE_CRADLE := ICON_FABRICATOR
const ICON_FABRICATION_SPOT := ICON_FABRICATOR
const ICON_STORAGE_BIN := ICON_STOCKPILE
const ICON_OUTLET_EXTENSION := ICON_CHARGE_PAD
const ICON_RUDIMENTARY_SENSOR := ICON_SENSOR
const ICON_SMALL_LIGHT_DEVICE := ICON_LIGHT
const ICON_LARGE_LIGHT_DEVICE := ICON_LIGHT

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
const WORKER_ATLAS_PATH := "res://resources/entities/worker_atlas.png"
const BOTS_ATLAS_PATH := "res://resources/entities/bots_atlas.png"
const WORKER_REGION_SIZE := Vector2(32, 32)
const BOT_REGION_SIZE := Vector2(32, 32)
const FACING_SOUTH: int = 0
const NEUTRAL_ROW: int = 0
const HOSTILE_ROW: int = 1
const PALETTE_WIDTH: float = 820.0
const PALETTE_HEIGHT: float = 200.0
const PALETTE_COLLAPSED_WIDTH: float = 132.0
const PALETTE_COLLAPSED_HEIGHT: float = 44.0
const TOP_STRIP_HEIGHT: float = 44.0
const WORKER_LIST_WIDTH: float = 220.0
const WORKER_LIST_MARGIN: float = 16.0
const WORKER_LIST_ROW_HEIGHT: float = 28.0
const WORKER_LIST_ROW_SEP: float = 4.0
const WORKER_LIST_INNER_PAD: float = 5.0
const WORKER_LIST_HEADER_HEIGHT: float = 18.0
const SELECTION_PANEL_WIDTH: float = 560.0
const SELECTION_PANEL_HEIGHT: float = 650.0
const WORKER_CARD_WIDTH: float = 440.0
const INSPECT_CARD_WIDTH: float = 300.0
const INSPECT_CARD_HEIGHT: float = 150.0
const PANEL_DRAG_BORDER_PX: float = 8.0

@export var designator_path: NodePath
@export var job_board_path: NodePath
@export var stockpile_manager_path: NodePath
@export var items_root_path: NodePath
@export var workers_root_path: NodePath
@export var structure_manager_path: NodePath
@export var camera_path: NodePath
@export var selection_controller_path: NodePath

var _designator: Designator
var _job_board: JobBoard
var _stockpile_manager: StockpileManager
var _items_root: Node2D
var _workers_root: Node2D
var _structure_manager: StructureManager
var _camera: CameraController
var _selection_controller: SelectionController

var _atlas: Texture2D
var _workshop_atlas: Texture2D
var _object_atlas: Texture2D
var _door_atlas: Texture2D
var _worker_atlas: Texture2D
var _bot_atlas: Texture2D
var _tab_group: ButtonGroup = ButtonGroup.new()
var _current_tab: StringName = TAB_ORDERS
var _current_building_subtab: StringName = TAB_BUILD_GENERAL
var _building_subtab_group: ButtonGroup = ButtonGroup.new()
var _building_subtab_row: HBoxContainer = null
var _building_subtab_buttons: Dictionary = {}     ## StringName -> Button
var _command_grid: GridContainer
var _active_label: Label
var _workers_label: Label
var _jobs_button: Button
var _jobs_popup: PanelContainer
var _jobs_popup_box: VBoxContainer
var _wisdom_label: Label
var _resource_labels: Dictionary = {}            ## int -> Label
var _resource_category_buttons: Dictionary = {}  ## int -> Button
var _resource_popups: Dictionary = {}            ## int -> PanelContainer
var _command_buttons: Dictionary = {}            ## int -> Button
var _delete_button: Button = null
var _tech_tree_panel: CanvasLayer = null
const TECH_TREE_SCENE: PackedScene = preload("res://scenes/ui/TechTreePanel.tscn")
var _selection_panel: PanelContainer
var _selection_box: VBoxContainer
var _palette_panel: PanelContainer
var _palette_box: VBoxContainer
var _palette_collapsed_label: Label
var _palette_collapsed: bool = false
var _npc_strip: BoxContainer
var _selected_workers: Array[Worker] = []
var _selected_structure_id: int = -1
var _selected_structure_anchor: Vector2i = Vector2i.ZERO
var _selected_stockpile: StockpileZone = null
var _selected_build_anchor: Vector2i = Pathfinder.UNREACHABLE
var _top_strip: PanelContainer
var _npc_panel: PanelContainer
var _inspect_panel: PanelContainer
var _inspect_box: VBoxContainer
var _inspected_node: Node = null
var _inspected_faction: int = 0
var _status_refresh_queued: bool = false
var _last_npc_strip_count: int = -1
var _npc_buttons_by_worker: Dictionary = {}       ## Worker -> Button
var _combat_tweens_by_worker: Dictionary = {}     ## Worker -> Tween
# Tracks the set of workers currently fighting so the auto-pause only fires
# on the *first* worker entering combat each engagement. As long as somebody
# is still fighting, additional `worker_entered_combat` signals do not
# re-pause the game; the set is cleared once everyone is back to non-combat.
var _workers_in_combat: Dictionary = {}           ## Worker -> true
var _drag_offsets: Dictionary = {}                ## Control -> Vector2 user-positioned offset (top-left in viewport coords; Vector2.INF if untouched)
var _dragging_panel: Control = null
## Re-entry guards. `_position_palette_panel` and `_position_selection_panel`
## modify their panels' anchors/offsets, which can fire the panel's `resized`
## signal — which is connected back to the same function. Without these flags
## a stable size never gets reached and GDScript blows the script stack.
var _positioning_palette: bool = false
var _positioning_selection: bool = false
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _last_dynamic_refresh_ms: int = 0
const DYNAMIC_REFRESH_INTERVAL_MS: int = 500


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_designator = get_node_or_null(designator_path) as Designator
	_job_board = get_node_or_null(job_board_path) as JobBoard
	_stockpile_manager = get_node_or_null(stockpile_manager_path) as StockpileManager
	_items_root = get_node_or_null(items_root_path) as Node2D
	_workers_root = get_node_or_null(workers_root_path) as Node2D
	_structure_manager = get_node_or_null(structure_manager_path) as StructureManager
	_camera = get_node_or_null(camera_path) as CameraController
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController
	_atlas = load(UI_ATLAS_PATH) as Texture2D
	_workshop_atlas = load(WORKSHOP_ATLAS_PATH) as Texture2D
	_object_atlas = load(OBJECT_ATLAS_PATH) as Texture2D
	_door_atlas = load(DOOR_ATLAS_PATH) as Texture2D
	_worker_atlas = load(WORKER_ATLAS_PATH) as Texture2D
	_bot_atlas = load(BOTS_ATLAS_PATH) as Texture2D

	_build_layout()
	_connect_signals()
	_set_tab(TAB_ORDERS)
	_refresh_all()

	# Dynamic HUD refresh is wall-clock based via `_process` so it doesn't
	# tick 3-4x faster on high game speed (a Timer node scales with
	# Engine.time_scale and would rebuild cards/labels well over twice a
	# second when the player fast-forwards).
	set_process(true)


func _connect_signals() -> void:
	if _designator != null:
		_designator.mode_changed.connect(_on_mode_changed)
	if _job_board != null:
		_job_board.job_added.connect(_on_job_changed)
		_job_board.job_completed.connect(_on_job_changed)
		_job_board.job_cancelled.connect(_on_job_changed)
	if _stockpile_manager != null:
		_stockpile_manager.stockpile_changed.connect(_schedule_status_refresh)
	EventBus.workers_selected.connect(_on_workers_selected)
	EventBus.structure_selected.connect(_on_structure_selected)
	EventBus.stockpile_selected.connect(_on_stockpile_selected)
	EventBus.build_job_selected.connect(_on_build_job_selected)
	EventBus.default_tile_clicked.connect(_on_default_tile_clicked)
	EventBus.bot_inspected.connect(_on_bot_inspected)
	EventBus.worker_entered_combat.connect(_on_worker_entered_combat)
	EventBus.combatant_died.connect(_on_combatant_died)
	EventBus.wisdom_changed.connect(_on_wisdom_changed)
	EventBus.tech_unlocked.connect(_on_tech_unlocked)
	SettingsManager.settings_changed.connect(_on_settings_changed)


func _build_layout() -> void:
	# Top Strip Container - centered horizontally, auto-sizes to badges.
	var top_strip := PanelContainer.new()
	top_strip.name = "TopStrip"
	top_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	top_strip.add_theme_stylebox_override("panel", _panel_textured_style("top_strip", COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 6.0, true))
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

	_jobs_button = _jobs_badge_button("jobs 0")
	status_row.add_child(_jobs_button)
	_build_jobs_popup()

	_active_label = _status_label("tool -")
	_active_label.add_theme_color_override("font_color", COLOR_ACCENT_AMBER)
	status_row.add_child(_badge_container(_active_label))

	status_row.add_child(_separator())

	for category in _resource_categories():
		var button := _resource_category_button(category)
		status_row.add_child(button)
		_resource_category_buttons[category] = button
		_build_resource_popup(category)

	# Wisdom (research currency). Color-tinted lavender to read as abstract.
	_wisdom_label = _status_label("wisdom 0")
	_wisdom_label.add_theme_color_override("font_color", Color(0.82, 0.78, 1.0))
	status_row.add_child(_badge_container(_wisdom_label))

	status_row.add_child(_separator())

	var tech_button := Button.new()
	tech_button.text = "Technology"
	tech_button.focus_mode = Control.FOCUS_NONE
	tech_button.custom_minimum_size = Vector2(110, 28)
	tech_button.add_theme_font_size_override("font_size", 12)
	tech_button.add_theme_stylebox_override("normal", _button_style(COLOR_BG_RAISED, COLOR_BORDER_DEFAULT))
	tech_button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
	tech_button.add_theme_stylebox_override("pressed", _button_style(Color(0.18, 0.14, 0.20, 1.0), COLOR_ACCENT_AMBER))
	tech_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tech_button.add_theme_color_override("font_color", Color(0.82, 0.78, 1.0))
	tech_button.add_theme_color_override("font_hover_color", Color.WHITE)
	tech_button.pressed.connect(_open_tech_tree)
	status_row.add_child(tech_button)

	var npc_panel := PanelContainer.new()
	npc_panel.name = "NpcStrip"
	npc_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	npc_panel.anchor_left = 0.0
	npc_panel.anchor_top = 0.0
	npc_panel.anchor_right = 0.0
	npc_panel.anchor_bottom = 0.0
	npc_panel.offset_left = WORKER_LIST_MARGIN
	npc_panel.offset_top = WORKER_LIST_MARGIN
	npc_panel.offset_right = WORKER_LIST_MARGIN + WORKER_LIST_WIDTH
	npc_panel.offset_bottom = WORKER_LIST_MARGIN + _npc_panel_height_for(0)
	npc_panel.add_theme_stylebox_override("panel", _panel_textured_style("npc_strip", COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 6.0, true))
	_npc_panel = npc_panel
	add_child(npc_panel)

	var npc_margin := MarginContainer.new()
	npc_margin.add_theme_constant_override("margin_left", int(WORKER_LIST_INNER_PAD))
	npc_margin.add_theme_constant_override("margin_top", int(WORKER_LIST_INNER_PAD))
	npc_margin.add_theme_constant_override("margin_right", int(WORKER_LIST_INNER_PAD))
	npc_margin.add_theme_constant_override("margin_bottom", int(WORKER_LIST_INNER_PAD))
	npc_panel.add_child(npc_margin)

	_npc_strip = VBoxContainer.new()
	_npc_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_strip.add_theme_constant_override("separation", int(WORKER_LIST_ROW_SEP))
	npc_margin.add_child(_npc_strip)

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
	palette.add_theme_stylebox_override("panel", _panel_textured_style("command_palette", COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 6.0, true))
	palette.gui_input.connect(_on_palette_gui_input)
	_palette_panel = palette
	add_child(palette)

	var palette_margin := MarginContainer.new()
	palette_margin.add_theme_constant_override("margin_left", 10)
	palette_margin.add_theme_constant_override("margin_top", 9)
	palette_margin.add_theme_constant_override("margin_right", 10)
	palette_margin.add_theme_constant_override("margin_bottom", 10)
	palette.add_child(palette_margin)

	var collapsed_label := Label.new()
	collapsed_label.text = "Designations"
	collapsed_label.visible = false
	collapsed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	collapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	collapsed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	collapsed_label.add_theme_font_size_override("font_size", 12)
	collapsed_label.add_theme_color_override("font_color", COLOR_ACCENT_AMBER)
	_palette_collapsed_label = collapsed_label
	palette_margin.add_child(collapsed_label)

	var palette_box := VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 8)
	_palette_box = palette_box
	palette_margin.add_child(palette_box)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	palette_box.add_child(tabs)

	_add_tab_button(tabs, TAB_ORDERS, "Orders")
	_add_tab_button(tabs, TAB_ZONES, "Zones")
	_add_tab_button(tabs, TAB_ROOMS, "Rooms")
	_add_tab_button(tabs, TAB_WORKSHOPS, "Workshops")
	_add_tab_button(tabs, TAB_BUILDING, "Building")
	_add_delete_button(tabs)

	# Building subtabs (General / Storage / Visibility / Objects). The row is
	# only made visible while the Building tab is active.
	_building_subtab_row = HBoxContainer.new()
	_building_subtab_row.add_theme_constant_override("separation", 4)
	_building_subtab_row.visible = false
	palette_box.add_child(_building_subtab_row)
	for subtab_id in BUILDING_SUBTABS:
		_add_building_subtab_button(_building_subtab_row, subtab_id, str(BUILDING_SUBTAB_LABELS[subtab_id]))

	_command_grid = GridContainer.new()
	_command_grid.columns = 5
	_command_grid.add_theme_constant_override("h_separation", 6)
	_command_grid.add_theme_constant_override("v_separation", 7)
	palette_box.add_child(_command_grid)

	_selection_panel = PanelContainer.new()
	_selection_panel.name = "SelectionPanel"
	_selection_panel.visible = false
	_selection_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_selection_panel.anchor_left = 0.0
	_selection_panel.anchor_top = 0.0
	_selection_panel.anchor_right = 0.0
	_selection_panel.anchor_bottom = 0.0
	_selection_panel.add_theme_stylebox_override("panel", _panel_textured_style("selection_panel", COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 5.0, true))
	add_child(_selection_panel)

	var selection_margin := MarginContainer.new()
	selection_margin.add_theme_constant_override("margin_left", 8)
	selection_margin.add_theme_constant_override("margin_top", 8)
	selection_margin.add_theme_constant_override("margin_right", 4)
	selection_margin.add_theme_constant_override("margin_bottom", 8)
	_selection_panel.add_child(selection_margin)

	var selection_scroll := ScrollContainer.new()
	selection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	selection_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	selection_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selection_margin.add_child(selection_scroll)

	_selection_box = VBoxContainer.new()
	_selection_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_selection_box.add_theme_constant_override("separation", 12)
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
	# Inspect card sits on top of the HUD strip; no outer panel chrome so it
	# doesn't look like a panel nested inside the larger HUD background.
	_inspect_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
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
	_position_selection_panel()
	_position_palette_panel()
	resized.connect(_position_selection_panel)
	resized.connect(_position_palette_panel)
	_palette_panel.resized.connect(_position_palette_panel)

	# Allow click-drag near panel edges to relocate the HUD panels around the
	# screen. gui_input fires before the panel's children consume the event,
	# so we only grab when the cursor sits in the outer border zone — clicks
	# on buttons inside still work normally.
	_palette_panel.gui_input.connect(_on_drag_panel_input.bind(_palette_panel))
	_npc_panel.gui_input.connect(_on_drag_panel_input.bind(_npc_panel))
	_top_strip.gui_input.connect(_on_drag_panel_input.bind(_top_strip))
	# The worker / selection info card is built dynamically when something is
	# selected, but the outer panel persists across selections, so a single
	# RMB-drag wiring at construction time is enough.
	_selection_panel.gui_input.connect(_on_drag_panel_input.bind(_selection_panel))


func _recenter_top_strip() -> void:
	if _top_strip == null:
		return
	if _has_user_drag_offset(_top_strip):
		return
	var w: float = _top_strip.size.x
	if w <= 0.0:
		w = _top_strip.get_combined_minimum_size().x
	if w <= 0.0:
		return
	_top_strip.offset_left = -w * 0.5
	_top_strip.offset_right = w * 0.5


func _has_user_drag_offset(panel: Control) -> bool:
	if not _drag_offsets.has(panel):
		return false
	return (_drag_offsets[panel] as Vector2) != Vector2.INF


func _on_drag_panel_input(event: InputEvent, panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or not panel.is_inside_tree():
		return
	# Secondary-button anywhere on the panel grabs it for dragging. The
	# primary button stays free for buttons/sliders inside the panel. Which
	# physical button counts as secondary depends on the swap-mouse-buttons
	# setting (defaults to right-click). We always consume RMB so it never
	# leaks out to SelectionController and crashes when there is no world
	# tile under the cursor (or fires an unintended order on the world tile
	# that happens to be behind the HUD).
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != SettingsManager.secondary_mouse_button():
			return
		if mb.pressed:
			_dragging_panel = panel
			_drag_grab_offset = panel.global_position - panel.get_global_mouse_position()
		else:
			if _dragging_panel == panel:
				_dragging_panel = null
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_panel == panel:
		var target: Vector2 = panel.get_global_mouse_position() + _drag_grab_offset
		var viewport_size: Vector2 = get_viewport_rect().size
		var panel_size: Vector2 = panel.size
		if panel_size.x <= 0.0 or panel_size.y <= 0.0:
			panel_size = panel.get_combined_minimum_size()
		target.x = clampf(target.x, 0.0, maxf(0.0, viewport_size.x - panel_size.x))
		target.y = clampf(target.y, 0.0, maxf(0.0, viewport_size.y - panel_size.y))
		_apply_panel_absolute_position(panel, target)
		_drag_offsets[panel] = target
		get_viewport().set_input_as_handled()


func _is_on_panel_drag_border(local: Vector2, rect: Rect2) -> bool:
	var b: float = PANEL_DRAG_BORDER_PX
	if local.x < rect.position.x or local.y < rect.position.y \
			or local.x > rect.position.x + rect.size.x \
			or local.y > rect.position.y + rect.size.y:
		return false
	return local.x <= rect.position.x + b \
		or local.y <= rect.position.y + b \
		or local.x >= rect.position.x + rect.size.x - b \
		or local.y >= rect.position.y + rect.size.y - b


func _apply_panel_absolute_position(panel: Control, top_left: Vector2) -> void:
	# Convert absolute top-left into anchor-relative offsets. We don't change
	# anchors here — the existing anchor presets stay, we just rewrite offsets
	# so the panel lands where the user dropped it.
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	var sz: Vector2 = panel.size
	panel.offset_left = top_left.x
	panel.offset_top = top_left.y
	panel.offset_right = top_left.x + sz.x
	panel.offset_bottom = top_left.y + sz.y


func _position_selection_panel() -> void:
	if _selection_panel == null or _positioning_selection:
		return
	if _has_user_drag_offset(_selection_panel):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var width: float = clampf(viewport_size.x * 0.34, 500.0, SELECTION_PANEL_WIDTH)
	if viewport_size.x < 900.0:
		width = viewport_size.x - 24.0
	var left: float = viewport_size.x - width - 16.0
	var top: float = 72.0
	var bottom: float = minf(viewport_size.y - 24.0, top + SELECTION_PANEL_HEIGHT)
	_positioning_selection = true
	_selection_panel.offset_left = left
	_selection_panel.offset_top = top
	_selection_panel.offset_right = left + width
	_selection_panel.offset_bottom = bottom
	_positioning_selection = false


func _position_palette_panel() -> void:
	if _palette_panel == null or _positioning_palette:
		return
	if _has_user_drag_offset(_palette_panel):
		return
	_positioning_palette = true
	# Anchor to bottom-center so width auto-sizes from content (tab row +
	# command grid) and we manually recenter horizontally.
	_palette_panel.anchor_left = 0.5
	_palette_panel.anchor_top = 1.0
	_palette_panel.anchor_right = 0.5
	_palette_panel.anchor_bottom = 1.0
	if _palette_collapsed:
		_palette_panel.offset_left = -PALETTE_COLLAPSED_WIDTH * 0.5
		_palette_panel.offset_top = -PALETTE_COLLAPSED_HEIGHT - 16.0
		_palette_panel.offset_right = PALETTE_COLLAPSED_WIDTH * 0.5
		_palette_panel.offset_bottom = -16.0
		_positioning_palette = false
		return
	# Use the larger of the explicit min-width and the actual measured width
	# so all designation tabs fit even when categories are added later.
	var measured: float = _palette_panel.get_combined_minimum_size().x
	var width: float = maxf(PALETTE_WIDTH, measured)
	_palette_panel.offset_left = -width * 0.5
	_palette_panel.offset_top = -PALETTE_HEIGHT - 16.0
	_palette_panel.offset_right = width * 0.5
	_palette_panel.offset_bottom = -16.0
	_positioning_palette = false


func _add_delete_button(parent: HBoxContainer) -> void:
	# Sits at the end of the tab row as a bold red toggle. Activates the
	# global DELETE designation mode that can wipe any player-built
	# structure, stockpile, room, or pending order under the cursor (RMB),
	# refunding 50% of build ingredients where applicable.
	var button := Button.new()
	button.text = "Delete"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(112, 32)
	button.add_theme_font_size_override("font_size", 13)
	button.tooltip_text = "Delete tool\nRight-click any player-built workshop, building, object, stockpile, or pending order to remove it.\nRefunds 50% of build ingredients where applicable."

	var normal_fill := Color(0.55, 0.16, 0.16, 0.92)
	var hover_fill := Color(0.78, 0.22, 0.22, 0.95)
	var pressed_fill := Color(0.92, 0.30, 0.26, 1.0)
	var red_border := Color(1.0, 0.42, 0.36, 0.95)
	button.add_theme_stylebox_override("normal", _button_style(normal_fill, red_border))
	button.add_theme_stylebox_override("hover", _button_style(hover_fill, red_border))
	button.add_theme_stylebox_override("pressed", _button_style(pressed_fill, Color(1.0, 0.6, 0.4, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.pressed.connect(_on_delete_button_pressed)
	parent.add_child(button)
	_delete_button = button


func _on_delete_button_pressed() -> void:
	if _designator == null:
		return
	_set_palette_collapsed(false)
	_designator.toggle_mode(Designator.Mode.DELETE)


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


func _add_building_subtab_button(parent: HBoxContainer, subtab: StringName, label_text: String) -> void:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.button_group = _building_subtab_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(86, 24)
	button.add_theme_font_size_override("font_size", 11)
	# Slightly subdued styling so the subtab row reads as secondary to the
	# main tab row above it.
	button.add_theme_stylebox_override("normal", _tab_style(Color(0.10, 0.12, 0.14, 0.35), Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", _tab_style(Color(0.16, 0.18, 0.20, 0.55), COLOR_ACCENT_MUTED))
	button.add_theme_stylebox_override("pressed", _tab_style(Color(0.18, 0.16, 0.12, 0.85), COLOR_ACCENT_AMBER))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.pressed.connect(_on_building_subtab_pressed.bind(subtab))
	parent.add_child(button)
	_building_subtab_buttons[subtab] = button


func _on_building_subtab_pressed(subtab: StringName) -> void:
	_current_building_subtab = subtab
	# Subtab changes only rebuild the command grid; the Building tab itself
	# stays selected.
	_render_current_tab()


func _set_tab(tab: StringName) -> void:
	_set_palette_collapsed(false)
	_current_tab = tab
	_render_current_tab()


func _render_current_tab() -> void:
	for child in _command_grid.get_children():
		_command_grid.remove_child(child)
		child.queue_free()
	_command_buttons.clear()

	# Building tab is a wrapper: render the subtab row and use the active
	# subtab as the effective source for `_commands_for_tab`.
	var is_building: bool = _current_tab == TAB_BUILDING
	if _building_subtab_row != null:
		_building_subtab_row.visible = is_building
	var effective_tab: StringName = _current_tab
	if is_building:
		effective_tab = _current_building_subtab
		var subtab_button := _building_subtab_buttons.get(_current_building_subtab) as Button
		if subtab_button != null:
			subtab_button.set_pressed_no_signal(true)

	for command in _commands_for_tab(effective_tab):
		var build_id: int = int(command.get("build_id", -1))
		var required_tech_id: StringName = StringName(command.get("required_tech_id", &""))
		var lock_build: bool = bool(command.get("lock_build", true))
		var icon_texture: Texture2D = null
		if build_id >= 0 and (effective_tab == TAB_WORKSHOPS or effective_tab == TAB_BUILD_GENERAL or effective_tab == TAB_STORAGE or effective_tab == TAB_VISIBILITY or effective_tab == TAB_OBJECTS):
			icon_texture = _structure_icon(build_id)
		_add_command_button(
			int(command["mode"]),
			command["label"] as String,
			command["tooltip"] as String,
			command["icon"] as Vector2i,
			build_id,
			icon_texture,
			required_tech_id,
			lock_build
		)
	_refresh_mode_buttons()


func _commands_for_tab(tab: StringName) -> Array[Dictionary]:
	match tab:
		TAB_ZONES:
			return [
				{"mode": Designator.Mode.STOCKPILE, "label": "Stockpile", "tooltip": "Stockpile\nPaint explored walkable cells for loose item storage.\nWorkers haul loose stacks here and merge same-kind stacks.", "icon": ICON_STOCKPILE},
			]
		TAB_ROOMS:
			return [
				{"mode": Designator.Mode.DESIGNATE_DOCK_ROOM, "label": "Dock Room", "tooltip": "Dock Room\nPersonal space for a bot to rest.\nMinimum 1x2 with a Dock Bed. One bot per room.\nMissing rooms tank mood over time.", "icon": ICON_DOCK},
				{"mode": Designator.Mode.DESIGNATE_RESEARCH_ROOM, "label": "Research", "tooltip": "Research Room\nMust contain a Research Bench.\nBots earn wisdom while seated and gather a small mood lift.", "icon": ICON_MEDITATION_PAD, "build_id": BuildBlueprint.Id.MEDITATION_PAD},
				{"mode": Designator.Mode.DESIGNATE_MECHANIC_ROOM, "label": "Mechanic", "tooltip": "Mechanic Room\nMust contain a Mechanic Dock.\nWhen valid, that dock heals room occupants faster.", "icon": ICON_MAINTENANCE_DOCK, "build_id": BuildBlueprint.Id.MAINTENANCE_DOCK, "required_tech_id": TechDatabase.MECHANIC_ROOM, "lock_build": false},
				{"mode": Designator.Mode.DESIGNATE_WORKSHOP_ROOM, "label": "Workshop", "tooltip": "Workshop Room\nMust be enclosed by walls + door, contain a light source object, and a workshop structure.\nWorkshops inside get a speed buff; outside any room they suffer a debuff.", "icon": ICON_FABRICATION_SPOT, "build_id": BuildBlueprint.Id.FABRICATION_SPOT},
			]
		TAB_WORKSHOPS:
			return [
				{"mode": Designator.Mode.BUILD_DOCK, "label": "Dock Bed", "tooltip": _build_tooltip(BuildBlueprint.Id.DOCK), "icon": ICON_DOCK, "build_id": BuildBlueprint.Id.DOCK},
				{"mode": Designator.Mode.BUILD_REPAIR_BENCH, "label": "Repair Bench", "tooltip": _build_tooltip(BuildBlueprint.Id.REPAIR_BENCH), "icon": ICON_REPAIR_BENCH, "build_id": BuildBlueprint.Id.REPAIR_BENCH},
				{"mode": Designator.Mode.BUILD_MEDITATION_PAD, "label": "Research", "tooltip": _build_tooltip(BuildBlueprint.Id.MEDITATION_PAD), "icon": ICON_MEDITATION_PAD, "build_id": BuildBlueprint.Id.MEDITATION_PAD},
				{"mode": Designator.Mode.BUILD_FABRICATION_SPOT, "label": "Craft Spot", "tooltip": _build_tooltip(BuildBlueprint.Id.FABRICATION_SPOT), "icon": ICON_FABRICATION_SPOT, "build_id": BuildBlueprint.Id.FABRICATION_SPOT},
				{"mode": Designator.Mode.BUILD_SENSOR, "label": "Sensor", "tooltip": _build_tooltip(BuildBlueprint.Id.SENSOR), "icon": ICON_SENSOR, "build_id": BuildBlueprint.Id.SENSOR},
				{"mode": Designator.Mode.BUILD_EXTRACTOR, "label": "Extractor", "tooltip": _build_tooltip(BuildBlueprint.Id.EXTRACTOR), "icon": ICON_EXTRACTOR, "build_id": BuildBlueprint.Id.EXTRACTOR},
				{"mode": Designator.Mode.BUILD_CHARGE_PAD, "label": "Charge", "tooltip": _build_tooltip(BuildBlueprint.Id.CHARGE_PAD), "icon": ICON_CHARGE_PAD, "build_id": BuildBlueprint.Id.CHARGE_PAD},
				{"mode": Designator.Mode.BUILD_FABRICATOR, "label": "Craft Bench", "tooltip": _build_tooltip(BuildBlueprint.Id.FABRICATOR), "icon": ICON_FABRICATOR, "build_id": BuildBlueprint.Id.FABRICATOR},
				{"mode": Designator.Mode.BUILD_PARTS_LOOM, "label": "Assembler", "tooltip": _build_tooltip(BuildBlueprint.Id.PARTS_LOOM), "icon": ICON_PARTS_LOOM, "build_id": BuildBlueprint.Id.PARTS_LOOM},
				{"mode": Designator.Mode.BUILD_MAINTENANCE_DOCK, "label": "Mech Dock", "tooltip": _build_tooltip(BuildBlueprint.Id.MAINTENANCE_DOCK), "icon": ICON_MAINTENANCE_DOCK, "build_id": BuildBlueprint.Id.MAINTENANCE_DOCK},
				{"mode": Designator.Mode.BUILD_FABRICATOR_ADVANCED, "label": "Fabricator", "tooltip": _build_tooltip(BuildBlueprint.Id.FABRICATOR_ADVANCED), "icon": ICON_FABRICATOR, "build_id": BuildBlueprint.Id.FABRICATOR_ADVANCED},
				{"mode": Designator.Mode.BUILD_SENTIENCE_CRADLE, "label": "Cradle", "tooltip": _build_tooltip(BuildBlueprint.Id.SENTIENCE_CRADLE), "icon": ICON_SENTIENCE_CRADLE, "build_id": BuildBlueprint.Id.SENTIENCE_CRADLE},
			]
		TAB_BUILD_GENERAL:
			return [
				{"mode": Designator.Mode.BUILD_WALL, "label": "Wall", "tooltip": _build_tooltip(BuildBlueprint.Id.WALL), "icon": ICON_WALL, "build_id": BuildBlueprint.Id.WALL},
				{"mode": Designator.Mode.BUILD_DOOR, "label": "Door", "tooltip": _build_tooltip(BuildBlueprint.Id.DOOR), "icon": ICON_DOOR, "build_id": BuildBlueprint.Id.DOOR},
				{"mode": Designator.Mode.PLACE_OUTLET_EXTENSION, "label": "Outlet Ext", "tooltip": _build_tooltip(BuildBlueprint.Id.OUTLET_EXTENSION), "icon": ICON_OUTLET_EXTENSION, "build_id": BuildBlueprint.Id.OUTLET_EXTENSION},
			]
		TAB_STORAGE:
			return [
				{"mode": Designator.Mode.PLACE_STORAGE_BIN, "label": "Storage Bin", "tooltip": _build_tooltip(BuildBlueprint.Id.STORAGE_BIN), "icon": ICON_STORAGE_BIN, "build_id": BuildBlueprint.Id.STORAGE_BIN},
			]
		TAB_VISIBILITY:
			return [
				{"mode": Designator.Mode.PLACE_SMALL_LIGHT_DEVICE, "label": "Small Light", "tooltip": _build_tooltip(BuildBlueprint.Id.SMALL_LIGHT_DEVICE), "icon": ICON_SMALL_LIGHT_DEVICE, "build_id": BuildBlueprint.Id.SMALL_LIGHT_DEVICE},
				{"mode": Designator.Mode.PLACE_LARGE_LIGHT_DEVICE, "label": "Large Light", "tooltip": _build_tooltip(BuildBlueprint.Id.LARGE_LIGHT_DEVICE), "icon": ICON_LARGE_LIGHT_DEVICE, "build_id": BuildBlueprint.Id.LARGE_LIGHT_DEVICE},
				{"mode": Designator.Mode.PLACE_RUDIMENTARY_SENSOR, "label": "Rud Sensor", "tooltip": _build_tooltip(BuildBlueprint.Id.RUDIMENTARY_SENSOR), "icon": ICON_RUDIMENTARY_SENSOR, "build_id": BuildBlueprint.Id.RUDIMENTARY_SENSOR},
			]
		TAB_OBJECTS:
			return []
		_:
			return [
				{"mode": Designator.Mode.MINE, "label": "Mine", "tooltip": "Mine\nMark wall, service core, or rich wall cells.\nWorkers dig adjacent cells and drop salvage resources.", "icon": ICON_MINE},
				{"mode": Designator.Mode.SCRAPE_BIOMASS, "label": "Scrape Biomass", "tooltip": "Scrape Biomass\nMark grass overgrowth cells.\nWorkers clear biomass tufts and may drop biomass for stockpiles.", "icon": ICON_STOCKPILE},
			]


func _add_command_button(
	mode: int,
	label_text: String,
	tooltip: String,
	icon_cell: Vector2i,
	build_id: int = -1,
	icon_texture: Texture2D = null,
	required_tech_id: StringName = &"",
	lock_build: bool = true
) -> void:
	var locked: bool = false
	var lock_tooltip: String = tooltip
	var gate: TechData = null
	if lock_build and build_id >= 0 and TechManager != null and not TechManager.is_build_unlocked(build_id):
		locked = true
		gate = TechManager.tech_unlocking(build_id)
		var gate_name: String = gate.display_name if gate != null else "an unknown tech"
		lock_tooltip = "Locked — research \"%s\"\n\n%s" % [gate_name, tooltip]
	if not locked and required_tech_id != &"" and TechManager != null and not TechManager.is_unlocked(required_tech_id):
		locked = true
		gate = TechDatabase.by_id(required_tech_id)
		var gate_name: String = gate.display_name if gate != null else "an unknown tech"
		lock_tooltip = "Locked — research \"%s\"\n\n%s" % [gate_name, tooltip]

	var button := Button.new()
	button.text = ("[locked] " + label_text) if locked else label_text
	button.tooltip_text = lock_tooltip
	button.toggle_mode = true
	button.disabled = locked
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(96, 38)
	button.icon = icon_texture if icon_texture != null else _atlas_icon(icon_cell)
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
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.08, 0.09, 0.10, 0.85), Color(0.30, 0.32, 0.34, 0.35)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if locked:
		button.add_theme_color_override("font_color", Color(0.50, 0.55, 0.60))
		button.add_theme_color_override("font_disabled_color", Color(0.50, 0.55, 0.60))
	else:
		button.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		button.add_theme_color_override("font_hover_color", COLOR_TEXT_LIGHT)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)

	button.pressed.connect(_on_command_pressed.bind(mode))
	_command_grid.add_child(button)
	_command_buttons[mode] = button


func _on_command_pressed(mode: int) -> void:
	if _designator == null:
		return
	_set_palette_collapsed(false)
	if mode == Designator.Mode.NONE:
		_designator.set_mode(Designator.Mode.NONE)
	else:
		_designator.toggle_mode(mode)


func _on_mode_changed(_mode: int) -> void:
	_refresh_mode_buttons()
	_schedule_status_refresh()


func _on_job_changed(_job: Job) -> void:
	if _selected_build_anchor != Pathfinder.UNREACHABLE and _job_board != null:
		if _job_board.build_job_at(_selected_build_anchor) == null:
			_selected_build_anchor = Pathfinder.UNREACHABLE
	_schedule_status_refresh()


func _schedule_status_refresh() -> void:
	if _status_refresh_queued:
		return
	_status_refresh_queued = true
	call_deferred("_refresh_status")


func _process(_delta: float) -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_dynamic_refresh_ms < DYNAMIC_REFRESH_INTERVAL_MS:
		return
	_last_dynamic_refresh_ms = now_ms
	_refresh_dynamic_status()


func _refresh_dynamic_status() -> void:
	_refresh_status()
	_refresh_combat_portraits()
	_refresh_npc_strip_if_needed()
	# Skip rebuilding the selection panel while the mouse is over it — the
	# rebuild destroys/recreates buttons, which kills hover state and eats
	# clicks (notably on the fabrication-spot craft order buttons). Explicit
	# selection / job / stockpile signal handlers will still refresh it.
	if not _mouse_over_selection_panel():
		_refresh_selection_panel()
	_refresh_inspect_card()


func _mouse_over_selection_panel() -> bool:
	if _selection_panel == null or not _selection_panel.visible:
		return false
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	return _selection_panel.get_global_rect().has_point(vp.get_mouse_position())


func _on_workers_selected(workers: Array[Worker]) -> void:
	_selected_workers = workers
	if not _selected_workers.is_empty():
		_set_palette_collapsed(false)
		_selected_structure_id = -1
		_selected_stockpile = null
		_selected_build_anchor = Pathfinder.UNREACHABLE
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
		_selected_stockpile = null
		_selected_build_anchor = Pathfinder.UNREACHABLE
		_inspected_node = null
		_inspected_faction = 0
	_refresh_selection_panel()
	_refresh_inspect_card()


func _on_stockpile_selected(zone: Node) -> void:
	_selected_stockpile = zone as StockpileZone
	if _selected_stockpile != null:
		_selected_workers.clear()
		_selected_structure_id = -1
		_selected_build_anchor = Pathfinder.UNREACHABLE
		_inspected_node = null
		_inspected_faction = 0
	_refresh_selection_panel()
	_refresh_inspect_card()


func _on_build_job_selected(anchor: Vector2i) -> void:
	_selected_build_anchor = anchor
	if anchor != Pathfinder.UNREACHABLE:
		_selected_workers.clear()
		_selected_structure_id = -1
		_selected_stockpile = null
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
		_selected_stockpile = null
		_selected_build_anchor = Pathfinder.UNREACHABLE
		_refresh_selection_panel()
	_refresh_inspect_card()


func _on_combatant_died(node: Node, _faction: int) -> void:
	if node == _inspected_node:
		_inspected_node = null
		_refresh_inspect_card()
	_stop_combat_blink(node)
	_workers_in_combat.erase(node)


func _on_wisdom_changed(new_total: float) -> void:
	if _wisdom_label != null:
		_wisdom_label.text = "wisdom %d" % int(roundf(new_total))


func _on_tech_unlocked(_tech_id: StringName) -> void:
	# A new tech can flip the unlocked state of structures — re-render the
	# current tab so locked rows refresh.
	_set_tab(_current_tab)


func _on_settings_changed() -> void:
	_position_palette_panel()
	_position_selection_panel()


func _on_default_tile_clicked(_grid: Vector2i) -> void:
	_set_palette_collapsed(true)


func _on_palette_gui_input(event: InputEvent) -> void:
	if not _palette_collapsed:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == SettingsManager.primary_mouse_button():
			_set_palette_collapsed(false)
			get_viewport().set_input_as_handled()


func _set_palette_collapsed(collapsed: bool) -> void:
	if _palette_panel == null:
		return
	if _palette_collapsed == collapsed:
		return
	_palette_collapsed = collapsed
	if _palette_box != null:
		_palette_box.visible = not collapsed
	if _palette_collapsed_label != null:
		_palette_collapsed_label.visible = collapsed
	_palette_panel.tooltip_text = "Expand designations" if collapsed else ""
	_position_palette_panel()


func _open_tech_tree() -> void:
	if _tech_tree_panel != null and is_instance_valid(_tech_tree_panel):
		return
	var panel: CanvasLayer = TECH_TREE_SCENE.instantiate() as CanvasLayer
	if panel == null:
		return
	_tech_tree_panel = panel
	panel.tree_exited.connect(_on_tech_tree_closed)
	add_child(panel)


func _on_tech_tree_closed() -> void:
	_tech_tree_panel = null


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
	if _delete_button != null:
		_delete_button.set_pressed_no_signal(active == Designator.Mode.DELETE)


func _refresh_status() -> void:
	_status_refresh_queued = false
	var worker_count: int = _workers_root.get_child_count() if _workers_root != null else 0
	var job_count: int = _job_board.pending_count() if _job_board != null else 0
	_workers_label.text = "workers %d" % worker_count
	if _jobs_button != null:
		_jobs_button.text = "jobs %d" % job_count
	if _jobs_popup != null and _jobs_popup.visible:
		_refresh_jobs_popup()
	_active_label.text = "tool %s" % (_designator.mode_label().to_lower() if _designator != null else "-")

	var counts: Dictionary = _resource_counts()
	for kind in _resource_labels.keys():
		var label := _resource_labels[kind] as Label
		if label != null:
			label.text = "%s %d" % [Item.kind_name(int(kind)), int(counts.get(kind, 0))]
	for category in _resource_category_buttons.keys():
		var button := _resource_category_buttons[category] as Button
		if button != null:
			button.text = "%s %d" % [Item.category_name(int(category)), _category_total(int(category), counts)]
			button.add_theme_color_override("font_color", Item.category_color(int(category)).lerp(Color.WHITE, 0.35))
	if _wisdom_label != null and TechManager != null:
		_wisdom_label.text = "wisdom %d" % int(roundf(TechManager.wisdom))
	_refresh_npc_strip_if_needed()


func _resource_counts() -> Dictionary:
	var counts: Dictionary = {
		Item.Kind.SCRAP: 0,
		Item.Kind.MECHANISM: 0,
		Item.Kind.PLATING: 0,
		Item.Kind.DATACORE: 0,
		Item.Kind.CHARGE_CELL: 0,
	}
	if _items_root != null:
		for child in _items_root.get_children():
			if not is_instance_valid(child):
				continue
			var item := child as Item
			if item != null:
				counts[item.kind] = int(counts.get(item.kind, 0)) + item.count
	if _stockpile_manager != null:
		for zone in _stockpile_manager.zones:
			if zone == null or not is_instance_valid(zone):
				continue
			for value in zone.occupant.values():
				# `value` may reference an Item that's been queue_freed but not
				# yet cleared from the stockpile bookkeeping. `value is Item`
				# would throw "left operand of `is` is a previously freed
				# instance" on a stale ref, so route through typeof + is_instance_valid
				# (Variant-level checks that don't dereference the Object).
				if value == null:
					continue
				if typeof(value) == TYPE_OBJECT and not is_instance_valid(value as Object):
					continue
				var item: Item = null
				if value is Item:
					item = value as Item
				elif value is Dictionary:
					var existing: Variant = (value as Dictionary).get(StockpileZone.R_EXISTING)
					if existing != null and typeof(existing) == TYPE_OBJECT and is_instance_valid(existing as Object):
						item = existing as Item
				if item != null and is_instance_valid(item):
					counts[item.kind] = int(counts.get(item.kind, 0)) + item.count
	return counts


func _tracked_item_kinds() -> Array[int]:
	return [
		Item.Kind.SCRAP,
		Item.Kind.BIOMASS,
		Item.Kind.MECHANISM,
		Item.Kind.PLATING,
		Item.Kind.DATACORE,
		Item.Kind.CHARGE_CELL,
		Item.Kind.STORAGE_BIN,
		Item.Kind.OUTLET_EXTENSION,
		Item.Kind.RUDIMENTARY_SENSOR,
		Item.Kind.SMALL_LIGHT_DEVICE,
		Item.Kind.LARGE_LIGHT_DEVICE,
	]


func _resource_categories() -> Array[int]:
	return [
		Item.Category.RAW,
		Item.Category.STRUCTURAL,
		Item.Category.MECHANICAL,
		Item.Category.DIGITAL,
		Item.Category.ENERGY,
	]


func _category_total(category: int, counts: Dictionary) -> int:
	var total: int = 0
	for kind in _tracked_item_kinds():
		if Item.kind_category(kind) == category:
			total += int(counts.get(kind, 0))
	return total


func _resource_category_button(category: int) -> Button:
	var button := Button.new()
	button.text = "%s 0" % Item.category_name(category)
	button.tooltip_text = _category_tooltip(category)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(104, 28)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _button_style(COLOR_BG_RAISED, COLOR_BORDER_DEFAULT))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.18, 0.14, 0.20, 1.0), COLOR_ACCENT_AMBER))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Item.category_color(category).lerp(Color.WHITE, 0.35))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.pressed.connect(_toggle_resource_popup.bind(category))
	return button


func _build_resource_popup(category: int) -> void:
	var popup := PanelContainer.new()
	popup.name = "ResourcePopup_%s" % Item.category_name(category)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.visible = false
	popup.z_index = 150
	popup.custom_minimum_size = Vector2(220, 0)
	popup.add_theme_stylebox_override("panel", _panel_textured_style("resource_popup", COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 4.0, true))
	add_child(popup)
	_resource_popups[category] = popup

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	for kind in _tracked_item_kinds():
		if Item.kind_category(kind) != category:
			continue
		var label := _status_label("%s 0" % Item.kind_name(kind))
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.custom_minimum_size = Vector2(190, 20)
		label.tooltip_text = "%s\n%s\nHow: %s" % [
			Item.kind_name(kind).capitalize(),
			Item.kind_description(kind),
			Item.acquisition_text(kind),
		]
		label.add_theme_color_override("font_color", Item.kind_color(kind).lerp(Color.WHITE, 0.35))
		box.add_child(label)
		_resource_labels[kind] = label


func _toggle_resource_popup(category: int) -> void:
	var popup := _resource_popups.get(category) as PanelContainer
	var button := _resource_category_buttons.get(category) as Button
	if popup == null or button == null:
		return
	if popup.visible:
		popup.visible = false
		return
	for other_key in _resource_popups.keys():
		if other_key == category:
			continue
		var other_popup := _resource_popups[other_key] as PanelContainer
		if other_popup != null:
			other_popup.visible = false
	var pos: Vector2 = button.global_position + Vector2(0.0, button.size.y + 3.0)
	popup.position = pos
	popup.visible = true


func _build_tooltip(blueprint_id: int) -> String:
	return BuildBlueprint.tooltip_text(blueprint_id)


func _category_tooltip(category: int) -> String:
	var lines: Array[String] = [Item.category_name(category).capitalize()]
	for kind in _tracked_item_kinds():
		if Item.kind_category(kind) == category:
			lines.append("%s: %s" % [Item.kind_name(kind), Item.acquisition_text(kind)])
	return "\n".join(lines)


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
	if _bot_atlas == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = _bot_atlas
	var row: int = HOSTILE_ROW if _inspected_faction == 2 else NEUTRAL_ROW
	icon.region = Rect2(Vector2(FACING_SOUTH * int(BOT_REGION_SIZE.x), row * int(BOT_REGION_SIZE.y)), BOT_REGION_SIZE)
	return icon


func _refresh_selection_panel() -> void:
	if _selection_panel == null or _selection_box == null:
		return
	for child in _selection_box.get_children():
		_selection_box.remove_child(child)
		child.queue_free()
	if _selected_build_anchor != Pathfinder.UNREACHABLE:
		_build_construction_card()
	elif _selected_structure_id >= 0:
		_build_structure_card()
	elif _selected_stockpile != null and is_instance_valid(_selected_stockpile):
		_build_stockpile_card()
	elif not _selected_workers.is_empty():
		_build_worker_cards()
	_selection_panel.visible = _selection_box.get_child_count() > 0


func _build_worker_cards() -> void:
	var live_workers: Array[Worker] = []
	for worker in _selected_workers:
		if worker != null and is_instance_valid(worker):
			live_workers.append(worker)
	_selected_workers = live_workers
	if live_workers.is_empty():
		return
	for worker in live_workers:
		_build_worker_detail_card(worker, 1)


func _add_worker_roster(workers: Array[Worker]) -> void:
	var roster_panel := PanelContainer.new()
	roster_panel.custom_minimum_size = Vector2(170, 0)
	roster_panel.add_theme_stylebox_override("panel", _panel_textured_style("roster_panel", COLOR_BG_RAISED, Color(0.30, 0.42, 0.46, 0.65), 5.0, false))
	_selection_box.add_child(roster_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	roster_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	_add_section_label(box, "%d selected" % workers.size())
	for worker in workers:
		var b := Button.new()
		b.text = worker.display_name()
		b.focus_mode = Control.FOCUS_NONE
		b.icon = _bot_icon()
		b.expand_icon = true
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_stylebox_override("normal", _button_style(COLOR_BG_DARK, COLOR_BORDER_DEFAULT))
		b.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
		b.add_theme_stylebox_override("pressed", _button_style(Color(0.20, 0.16, 0.10, 1.0), COLOR_ACCENT_AMBER))
		b.pressed.connect(_focus_worker.bind(worker))
		box.add_child(b)


func _build_worker_detail_card(worker: Worker, _selected_count: int) -> void:
	var card_panel := PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(WORKER_CARD_WIDTH, 0)
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_panel.add_theme_stylebox_override("panel", _panel_textured_style("worker_card", COLOR_BG_RAISED, Color(0.30, 0.42, 0.46, 0.65), 5.0, false))
	_selection_box.add_child(card_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	card_panel.add_child(margin)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	margin.add_child(card)

	_add_worker_header(card, worker)
	_add_worker_pause_button(card, worker)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	card.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 7)
	columns.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 7)
	columns.add_child(right)

	_add_worker_summary(left, worker)
	_add_meter(left, "energy", worker.energy_ratio(), COLOR_METER_LOW if worker.energy_ratio() < 0.3 else COLOR_METER_GOOD)
	_add_meter(left, "condition", worker.condition_ratio(), Color(0.95, 0.52, 0.38))
	_add_meter(left, "mental exhaustion", worker.mental_tiredness_ratio(), Color(0.72, 0.58, 1.0))
	_add_meter(left, "social", worker.social_ratio(), Color(0.55, 0.85, 0.55))
	var mood_color: Color = Color(0.96, 0.5, 0.32) if worker.mood_ratio() < 0.4 else Color(0.95, 0.85, 0.4)
	_add_meter(left, "mood (%s)" % worker.mood_label(), worker.mood_ratio(), mood_color)

	var needs: Array[String] = worker.unsatisfied_needs()
	_add_section_label(right, "needs")
	if needs.is_empty():
		_add_status_banner(right, "satisfied", COLOR_METER_GOOD)
	else:
		_add_status_banner(right, ", ".join(needs), Color(1.0, 0.5, 0.35))
	_add_history_panel(right, worker)
	_add_limb_grid(right, worker)


func _add_worker_pause_button(parent: Control, worker: Worker) -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.button_pressed = worker.is_paused()
	button.text = "Resume Worker" if worker.is_paused() else "Pause Worker"
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", _button_style(COLOR_BG_DARK, COLOR_BORDER_DEFAULT))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.30, 0.20, 0.10, 1.0), COLOR_ACCENT_AMBER))
	button.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.toggled.connect(_on_worker_pause_toggled.bind(worker))
	parent.add_child(button)


func _on_worker_pause_toggled(pressed: bool, worker: Worker) -> void:
	if worker == null or not is_instance_valid(worker):
		return
	worker.set_paused(pressed)
	_schedule_status_refresh()


func _add_worker_header(parent: Control, worker: Worker) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var portrait := TextureRect.new()
	portrait.texture = _bot_icon()
	portrait.custom_minimum_size = Vector2(28, 28)
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(portrait)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_box)

	var name_label := Label.new()
	name_label.text = worker.display_name()
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_box.add_child(name_label)

	var state_label := Label.new()
	state_label.text = worker.state_label()
	state_label.add_theme_font_size_override("font_size", 11)
	state_label.add_theme_color_override("font_color", COLOR_ACCENT_CYAN)
	state_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_box.add_child(state_label)


func _add_worker_summary(parent: Control, worker: Worker) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	_add_metric_chip(grid, "job", worker.job_label(), COLOR_ACCENT_AMBER)
	_add_metric_chip(grid, "carry", worker.carried_label(), COLOR_TEXT_LIGHT)


func _add_metric_chip(parent: Control, key: String, value: String, color: Color) -> void:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(96, 38)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _panel_textured_style("resource_chip", Color(0.06, 0.075, 0.085, 0.88), Color(0.24, 0.30, 0.33, 0.62), 4.0, false))
	parent.add_child(chip)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	chip.add_child(box)

	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 9)
	key_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	box.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", color)
	value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(value_label)


func _add_section_label(parent: Control, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	parent.add_child(label)


func _add_status_banner(parent: Control, text_value: String, color: Color) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _add_limb_grid(parent: Control, worker: Worker) -> void:
	_add_section_label(parent, "limbs")
	var grid := GridContainer.new()
	# Two columns of {name, %, bar} stacks. Bars make damaged limbs read at a
	# glance instead of forcing the player to scan percent text.
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	var limb_lines: Array[String] = worker.limb_status_lines()
	var limb_ratios: Array[float] = worker.limb_condition_ratios()
	for i in limb_lines.size():
		var limb_line: String = limb_lines[i]
		var ratio: float = limb_ratios[i] if i < limb_ratios.size() else 1.0
		var limb_name: String = limb_line
		var pct: int = int(roundf(ratio * 100.0))
		var split: int = limb_line.rfind(" ")
		if split >= 0:
			limb_name = limb_line.substr(0, split)
		var color: Color = COLOR_METER_GOOD
		if pct < 30:
			color = Color(1.0, 0.42, 0.32)
		elif pct < 70:
			color = Color(0.98, 0.78, 0.32)
		_add_limb_cell(grid, limb_name, pct, ratio, color)


func _add_limb_cell(parent: Control, limb_name: String, pct: int, ratio: float, color: Color) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 1)
	parent.add_child(cell)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	cell.add_child(row)

	var name_label := Label.new()
	name_label.text = limb_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = "%d%%" % pct
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	row.add_child(value_label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.10, 0.95)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.corner_radius_top_left = 2
	fg.corner_radius_top_right = 2
	fg.corner_radius_bottom_left = 2
	fg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	cell.add_child(bar)


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
	if int(status["id"]) == BuildBlueprint.Id.FABRICATION_SPOT:
		_add_card_line(card, "orders", "%d queued" % int(status.get("craft_orders", 0)))
		var craft_missing: String = status.get("craft_missing_stockpile", "") as String
		if not craft_missing.is_empty():
			_add_card_line(card, "stockpile missing", craft_missing, Color(1.0, 0.5, 0.35))
		_add_fabrication_controls(card)
	elif BuildBlueprint.is_worker_operated(int(status["id"])):
		_add_card_line(card, "job list", "%d operation queued" % int(status.get("operation_orders", 0)))


func _add_fabrication_controls(parent: Control) -> void:
	_add_section_label(parent, "craft orders")
	for object_kind in Item.craftable_object_kinds():
		var button := Button.new()
		button.text = "Make " + Item.kind_name(object_kind)
		button.tooltip_text = "%s\nCost: %s\nCraft: %.0fs" % [
			Item.kind_name(object_kind).capitalize(),
			Item.recipe_text(Item.craft_recipe(object_kind)),
			Item.craft_duration(object_kind),
		]
		button.custom_minimum_size = Vector2(180, 30)
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_stylebox_override("normal", _button_style(COLOR_BG_RAISED, COLOR_BORDER_DEFAULT))
		button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.20, 0.16, 0.10, 1.0), COLOR_ACCENT_AMBER))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_color_override("font_color", Item.kind_color(object_kind).lerp(Color.WHITE, 0.35))
		button.pressed.connect(_on_craft_order_pressed.bind(object_kind))
		parent.add_child(button)
	var clear := Button.new()
	clear.text = "Clear orders"
	clear.tooltip_text = "Clear craft orders\nCancels queued fabrication jobs at this spot."
	clear.custom_minimum_size = Vector2(180, 30)
	clear.add_theme_font_size_override("font_size", 11)
	clear.add_theme_stylebox_override("normal", _button_style(COLOR_BG_RAISED, COLOR_BORDER_DEFAULT))
	clear.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
	clear.add_theme_stylebox_override("pressed", _button_style(Color(0.20, 0.16, 0.10, 1.0), COLOR_ACCENT_AMBER))
	clear.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	clear.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	clear.pressed.connect(_on_clear_craft_orders_pressed)
	parent.add_child(clear)


func _on_craft_order_pressed(object_kind: int) -> void:
	if _structure_manager == null:
		return
	if _structure_manager.add_craft_order(_selected_structure_anchor, object_kind):
		_refresh_status()
		_refresh_selection_panel()


func _on_clear_craft_orders_pressed() -> void:
	if _structure_manager == null or not _structure_manager.has_method("clear_craft_orders"):
		return
	_structure_manager.call("clear_craft_orders", _selected_structure_anchor)
	_refresh_status()
	_refresh_selection_panel()


func _build_stockpile_card() -> void:
	if _selected_stockpile == null or not is_instance_valid(_selected_stockpile):
		_selected_stockpile = null
		return
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(360, 0)
	card.add_theme_constant_override("separation", 5)
	_selection_box.add_child(card)
	_add_card_title(card, "Stockpile")
	_add_card_line(card, "cells", "%d" % _selected_stockpile.cells.size())
	_add_card_line(card, "stacks", "%d / %d" % [_selected_stockpile.stack_count(), _selected_stockpile.stack_capacity()])
	_add_card_line(card, "items", "%d / %d" % [_selected_stockpile.stored_count(), _selected_stockpile.capacity()])
	var counts: Dictionary = _selected_stockpile.resource_counts()
	if counts.is_empty():
		_add_card_line(card, "resources", "empty", COLOR_TEXT_MUTED)
		return
	_add_section_label(card, "resources")
	for kind in _tracked_item_kinds():
		var count: int = int(counts.get(kind, 0))
		if count <= 0:
			continue
		_add_card_line(card, Item.kind_name(kind), "%d" % count, Item.kind_color(kind).lerp(Color.WHITE, 0.35))


func _build_construction_card() -> void:
	if _job_board == null:
		return
	var build: BuildJob = _job_board.build_job_at(_selected_build_anchor)
	if build == null:
		_selected_build_anchor = Pathfinder.UNREACHABLE
		return
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	card.add_theme_constant_override("separation", 6)
	_selection_box.add_child(card)
	_add_card_title(card, "Building " + BuildBlueprint.display_name(build.blueprint_id).capitalize())
	_add_card_line(card, "grid", "%d,%d" % [build.anchor.x, build.anchor.y])
	_add_card_line(card, "cost", BuildBlueprint.ingredients_text(build.blueprint_id))
	_add_card_line(card, "delivered", build.delivered_items_text())
	_add_card_line(card, "missing", build.missing_items_text())
	_add_meter(card, "build progress", clampf(build.progress / build.build_duration(), 0.0, 1.0), COLOR_ACCENT_AMBER)
	_add_card_line(card, "refund", build.refund_items_text(), COLOR_ACCENT_CYAN)
	var info := Label.new()
	info.text = "Remove returns 50% of delivered resources."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	card.add_child(info)
	var remove := Button.new()
	remove.text = "Remove"
	remove.tooltip_text = "Cancel construction\nReturns 50% of delivered resources."
	remove.custom_minimum_size = Vector2(132, 34)
	remove.add_theme_font_size_override("font_size", 12)
	remove.add_theme_stylebox_override("normal", _button_style(Color(0.18, 0.07, 0.07, 0.95), Color(0.70, 0.22, 0.18, 0.78)))
	remove.add_theme_stylebox_override("hover", _button_style(Color(0.26, 0.10, 0.09, 0.98), Color(1.0, 0.32, 0.24, 0.95)))
	remove.add_theme_stylebox_override("pressed", _button_style(Color(0.34, 0.12, 0.10, 1.0), Color(1.0, 0.38, 0.28, 1.0)))
	remove.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	remove.pressed.connect(_on_remove_build_pressed.bind(build.anchor))
	card.add_child(remove)


func _on_remove_build_pressed(anchor: Vector2i) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or not scene.has_method("cancel_build_with_refund"):
		return
	var removed: bool = scene.call("cancel_build_with_refund", anchor) as bool
	if removed:
		_selected_build_anchor = Pathfinder.UNREACHABLE
		_refresh_status()


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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	value.text = "%d%%" % int(roundf(clampf(ratio, 0.0, 1.0) * 100.0))
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	row.add_child(value)
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
	scroll.custom_minimum_size = Vector2(240.0, HISTORY_VISIBLE_ROWS * 16)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(230.0, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)

	var history: Array[String] = worker.action_history()
	history.reverse()
	for entry in history:
		var label := Label.new()
		label.text = entry
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(220.0, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
		box.add_child(label)


func _refresh_npc_strip() -> void:
	if _npc_strip == null:
		return
	for worker_key in _combat_tweens_by_worker.keys():
		_stop_combat_blink(worker_key as Node)
	_npc_buttons_by_worker.clear()
	for child in _npc_strip.get_children():
		_npc_strip.remove_child(child)
		child.queue_free()
	var rows: int = 0
	if _workers_root != null:
		for child in _workers_root.get_children():
			var worker := child as Worker
			if worker == null:
				continue
			var button := Button.new()
			button.text = worker.display_name()
			button.focus_mode = Control.FOCUS_NONE
			button.icon = _bot_icon()
			button.expand_icon = true
			button.custom_minimum_size = Vector2(0, WORKER_LIST_ROW_HEIGHT)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 12)
			button.add_theme_stylebox_override("normal", _button_style(COLOR_BG_RAISED, COLOR_BORDER_DEFAULT))
			button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED))
			button.add_theme_stylebox_override("pressed", _button_style(Color(0.20, 0.16, 0.10, 1.0), COLOR_ACCENT_AMBER))
			button.pressed.connect(_focus_worker.bind(worker))
			_npc_strip.add_child(button)
			_npc_buttons_by_worker[worker] = button
			if worker.state_label() == "fighting":
				_start_combat_blink(worker, button)
			rows += 1
	_last_npc_strip_count = rows
	_resize_npc_panel(rows)


func _resize_npc_panel(rows: int) -> void:
	if _npc_panel == null:
		return
	_npc_panel.offset_bottom = _npc_panel.offset_top + _npc_panel_height_for(rows)


func _npc_panel_height_for(rows: int) -> float:
	var inner_pad: float = WORKER_LIST_INNER_PAD * 2.0
	if rows <= 0:
		return inner_pad + WORKER_LIST_HEADER_HEIGHT
	var body: float = float(rows) * WORKER_LIST_ROW_HEIGHT + float(rows - 1) * WORKER_LIST_ROW_SEP
	return inner_pad + body


func _refresh_npc_strip_if_needed() -> void:
	var count: int = _workers_root.get_child_count() if _workers_root != null else 0
	if count != _last_npc_strip_count:
		_refresh_npc_strip()


func _focus_worker(worker: Worker) -> void:
	if worker == null or not is_instance_valid(worker) or _camera == null:
		return
	if _selected_workers.size() == 1 and _selected_workers[0] == worker:
		_selected_workers.clear()
		if _selection_controller != null:
			_selection_controller.clear_selection()
		_refresh_selection_panel()
		_refresh_inspect_card()
		return
	_selected_workers = [worker]
	_selected_structure_id = -1
	_selected_stockpile = null
	_selected_build_anchor = Pathfinder.UNREACHABLE
	_inspected_node = null
	_inspected_faction = 0
	if _selection_controller != null:
		var picked: Array[Worker] = [worker]
		_selection_controller.select_workers(picked)
	_refresh_selection_panel()
	_refresh_inspect_card()
	_camera.center_on(worker.global_position)


func _on_worker_entered_combat(worker: Node) -> void:
	if worker == null or not is_instance_valid(worker):
		return
	# Only pause when this is a *fresh* engagement. As long as another worker
	# was already fighting, the player has already been alerted; re-pausing
	# on every individual attack thereafter was the original bug.
	var any_in_combat: bool = not _workers_in_combat.is_empty()
	_workers_in_combat[worker] = true
	if not any_in_combat:
		GameState.set_game_speed(0.0)
	var button := _npc_buttons_by_worker.get(worker) as Button
	if button != null:
		_start_combat_blink(worker, button)


func _refresh_combat_portraits() -> void:
	for worker_key in _combat_tweens_by_worker.keys():
		var worker := worker_key as Worker
		if worker == null or not is_instance_valid(worker) or worker.state_label() != "fighting":
			_stop_combat_blink(worker_key as Node)
			_workers_in_combat.erase(worker_key)
	# Drop any tracked worker that has died or is no longer in the tree so the
	# next combat is treated as a fresh engagement.
	for w_key in _workers_in_combat.keys():
		var w := w_key as Worker
		if w == null or not is_instance_valid(w) or w.state_label() != "fighting":
			_workers_in_combat.erase(w_key)


func _start_combat_blink(worker: Node, button: Button) -> void:
	if _combat_tweens_by_worker.has(worker):
		return
	button.modulate = Color.WHITE
	var tween: Tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "modulate", Color(1.0, 0.35, 0.35, 1.0), 0.6)
	tween.tween_property(button, "modulate", Color.WHITE, 0.6)
	_combat_tweens_by_worker[worker] = tween


func _stop_combat_blink(worker: Node) -> void:
	if worker == null:
		return
	var tween := _combat_tweens_by_worker.get(worker) as Tween
	if tween != null and is_instance_valid(tween):
		tween.kill()
	_combat_tweens_by_worker.erase(worker)
	var button := _npc_buttons_by_worker.get(worker) as Button
	if button != null:
		button.modulate = Color.WHITE


func _bot_icon() -> Texture2D:
	if _worker_atlas == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = _worker_atlas
	icon.region = Rect2(Vector2.ZERO, WORKER_REGION_SIZE)
	return icon


func _atlas_icon(cell: Vector2i) -> Texture2D:
	if _atlas == null:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = _atlas
	icon.region = Rect2(Vector2(cell * ICON_CELL_SIZE), Vector2(ICON_CELL_SIZE))
	return icon


func _structure_icon(build_id: int) -> Texture2D:
	var icon := AtlasTexture.new()
	if BuildBlueprint.is_object_placement(build_id):
		var object_kind: int = BuildBlueprint.object_item_kind(build_id)
		var object_index: int = Item.object_atlas_index(object_kind)
		if _object_atlas == null or object_index < 0:
			return null
		icon.atlas = _object_atlas
		icon.region = Rect2(Vector2(object_index * ICON_CELL_SIZE.x, 0), Vector2(ICON_CELL_SIZE))
		return icon
	if build_id == BuildBlueprint.Id.DOOR:
		if _door_atlas == null:
			return null
		icon.atlas = _door_atlas
		icon.region = Rect2(Vector2.ZERO, Vector2(ICON_CELL_SIZE))
		return icon
	if not BuildBlueprint.is_workshop(build_id):
		return null
	var workshop_index: int = BuildBlueprint.workshop_atlas_index(build_id)
	if _workshop_atlas == null or workshop_index < 0:
		return null
	icon.atlas = _workshop_atlas
	icon.region = Rect2(Vector2(workshop_index * WORKSHOP_ICON_SOURCE_SIZE.x, 0), Vector2(WORKSHOP_ICON_SOURCE_SIZE))
	return icon


func _status_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	return label


# Same look as `_badge_container` but built on a Button so the badge becomes
# clickable. Used by the jobs badge to open a dropdown listing pending jobs.
func _jobs_badge_button(initial_text: String) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = initial_text
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _panel_textured_style("wisdom_badge", COLOR_BG_RAISED, Color(0.29, 0.32, 0.35, 0.46), 3.0, false))
	btn.add_theme_stylebox_override("hover", _panel_textured_style("wisdom_badge", Color(0.16, 0.18, 0.20, 0.95), COLOR_ACCENT_MUTED, 3.0, false))
	btn.add_theme_stylebox_override("pressed", _panel_textured_style("wisdom_badge", Color(0.20, 0.16, 0.10, 1.0), COLOR_ACCENT_AMBER, 3.0, false))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_toggle_jobs_popup)
	return btn


func _build_jobs_popup() -> void:
	var popup := PanelContainer.new()
	popup.name = "JobsPopup"
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.visible = false
	popup.z_index = 150
	popup.custom_minimum_size = Vector2(260, 0)
	popup.add_theme_stylebox_override("panel", _panel_textured_style("jobs_popup", COLOR_BG_DARK, COLOR_BORDER_DEFAULT, 4.0, true))
	add_child(popup)
	_jobs_popup = popup

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	popup.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(244, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	_jobs_popup_box = VBoxContainer.new()
	_jobs_popup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jobs_popup_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_jobs_popup_box)


func _toggle_jobs_popup() -> void:
	if _jobs_popup == null or _jobs_button == null:
		return
	if _jobs_popup.visible:
		_jobs_popup.visible = false
		return
	# Close any other popups so the screen doesn't stack overlapping dropdowns.
	for other_popup in _resource_popups.values():
		var p := other_popup as PanelContainer
		if p != null:
			p.visible = false
	_refresh_jobs_popup()
	var pos: Vector2 = _jobs_button.global_position + Vector2(0.0, _jobs_button.size.y + 3.0)
	_jobs_popup.position = pos
	_jobs_popup.visible = true


func _refresh_jobs_popup() -> void:
	if _jobs_popup_box == null:
		return
	for child in _jobs_popup_box.get_children():
		_jobs_popup_box.remove_child(child)
		child.queue_free()
	if _job_board == null or _job_board.pending.is_empty():
		var empty := Label.new()
		empty.text = "No pending jobs."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		_jobs_popup_box.add_child(empty)
		return
	# Snapshot the list — cancelling mutates pending mid-iteration.
	var jobs: Array[Job] = []
	for job in _job_board.pending:
		jobs.append(job)
	for job in jobs:
		_add_jobs_popup_row(job)


func _add_jobs_popup_row(job: Job) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_jobs_popup_box.add_child(row)

	var label := Label.new()
	label.text = JobBoard.describe_job(job)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)

	if job.claimed_by != null:
		var claimed := Label.new()
		claimed.text = "active"
		claimed.add_theme_font_size_override("font_size", 9)
		claimed.add_theme_color_override("font_color", COLOR_ACCENT_AMBER)
		row.add_child(claimed)

	var cancel_btn := Button.new()
	cancel_btn.text = "x"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.custom_minimum_size = Vector2(22, 20)
	cancel_btn.add_theme_font_size_override("font_size", 11)
	cancel_btn.add_theme_stylebox_override("normal", _button_style(COLOR_BG_RAISED, Color(0.55, 0.20, 0.20, 0.8)))
	cancel_btn.add_theme_stylebox_override("hover", _button_style(Color(0.28, 0.10, 0.10, 0.95), Color(0.95, 0.32, 0.28, 1.0)))
	cancel_btn.add_theme_stylebox_override("pressed", _button_style(Color(0.40, 0.15, 0.15, 1.0), Color(1.0, 0.5, 0.4, 1.0)))
	cancel_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.50))
	cancel_btn.tooltip_text = "Cancel this job order"
	cancel_btn.pressed.connect(_on_cancel_job.bind(job))
	row.add_child(cancel_btn)


func _on_cancel_job(job: Job) -> void:
	if _job_board == null or job == null:
		return
	_job_board.cancel_job(job)
	# Repopulate to reflect the new pending list.
	_refresh_jobs_popup()


# Wraps a label in a neat panel "badge" for consistent visual separation
func _badge_container(content_label: Label) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _panel_textured_style(
		"wisdom_badge",
		COLOR_BG_RAISED,
		Color(0.29, 0.32, 0.35, 0.46),
		3.0,
		false,
	))

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


## Returns a `StyleBoxTexture` backed by the placeholder PNG at
## `resources/ui/panels/<panel_name>.png` so dropping in real art there
## immediately retextures the panel. Falls back to the legacy
## `_panel_style` flat fill if the texture is missing on disk.
##
## See `resources/ui/panels/README.md` for the 9-slice contract (48x48
## tile, 16 px corners).
func _panel_textured_style(panel_name: String, fallback_fill: Color, fallback_border: Color, radius: float, with_shadow: bool = false) -> StyleBox:
	var texture: Texture2D = _panel_texture(panel_name)
	# If a panel doesn't have its own PNG yet, reuse selection_panel.png as a
	# project-wide default so we stop drawing UI chrome from code.
	if texture == null:
		texture = _panel_texture("selection_panel")
	if texture == null:
		return _panel_style(fallback_fill, fallback_border, radius, with_shadow)
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 16.0
	style.texture_margin_top = 16.0
	style.texture_margin_right = 16.0
	style.texture_margin_bottom = 16.0
	return style


static func _panel_texture(panel_name: String) -> Texture2D:
	var path: String = "res://resources/ui/panels/%s.png" % panel_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


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
