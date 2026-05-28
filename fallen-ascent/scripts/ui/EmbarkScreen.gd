extends Control
##
## Embark customization screen (RimWorld/Dwarf-Fortress style). Players assemble
## their starting crew: each worker has a name, a randomized personality, a role
## (specialty that seeds skills + grants a small buff) and a Cogmind-style part
## loadout bought from a per-embark point pool. Achievement points permanently
## unlock higher part tiers, extra worker slots, and manual personality choice
## via the in-screen store.
##
## Personalities are randomized by default and can only be rerolled (per worker
## or crew-wide) UNLESS the player has bought the manual-personality unlock.
## Parts start empty; randomizing a worker also rolls a random part loadout that
## fits the pool budget and unlocked tier.
##
## Emits `embark_confirmed(loadouts: Array)` where each entry is a WorkerLoadout
## resource; Main stashes them on GameState and WorkerSpawner applies them.
##

signal embark_confirmed(loadouts: Array)
signal embark_cancelled

## Pool points granted per worker slot. Total budget scales with crew size so a
## bigger crew can still field basic kits, but premium parts force trade-offs.
const POOL_PER_WORKER: int = 12

## Display order + labels for the full derived-stat readout on each card.
const STAT_DISPLAY: Array[Dictionary] = [
	{"key": "move_speed", "label": "Move Speed", "fmt": "int"},
	{"key": "max_hp", "label": "Max Integrity", "fmt": "int"},
	{"key": "armor", "label": "Armor Rating", "fmt": "int"},
	{"key": "bash", "label": "Bash DMG", "fmt": "range"},
	{"key": "carry", "label": "Carry Cap", "fmt": "int"},
	{"key": "sight", "label": "Sensors", "fmt": "plus"},
	{"key": "work_speed", "label": "Work Speed", "fmt": "mult"},
	{"key": "mine_speed", "label": "Mining Rate", "fmt": "mult"},
	{"key": "build_speed", "label": "Construction", "fmt": "mult"},
	{"key": "wisdom", "label": "Computation", "fmt": "mult"},
	{"key": "energy_recharge", "label": "Recharge Efficiency", "fmt": "mult"},
	{"key": "energy_drain", "label": "Energy Drain", "fmt": "mult"},
	{"key": "dodge", "label": "Evasion Rate", "fmt": "pct"},
	{"key": "mood_baseline", "label": "Cognitive Base", "fmt": "int"},
]

var _loadouts: Array[WorkerLoadout] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _selected_worker_index: int = 0


func _ready() -> void:
	_rng.randomize()
	# Skin the embark buttons with the shared worker-card texture.
	theme = UiStyle.button_theme()
	_sync_loadout_count()
	_build_ui()


# ---- crew / pool model ------------------------------------------------------

func _slot_count() -> int:
	return AchievementManager.starting_worker_slots()


func _pool_total() -> int:
	return _slot_count() * POOL_PER_WORKER


func _pool_used() -> int:
	var sum: int = 0
	for loadout in _loadouts:
		sum += loadout.pool_cost()
	return sum


func _pool_remaining() -> int:
	return _pool_total() - _pool_used()


## Resize `_loadouts` to match the unlocked slot count, keeping existing builds.
func _sync_loadout_count() -> void:
	var target: int = _slot_count()
	while _loadouts.size() < target:
		_loadouts.append(_random_loadout())
	while _loadouts.size() > target:
		_loadouts.pop_back()
	
	_selected_worker_index = clampi(_selected_worker_index, 0, max(0, _loadouts.size() - 1))


## A fresh worker: random name + personality, default role, EMPTY parts. Parts
## are only filled by an explicit randomize action.
func _random_loadout() -> WorkerLoadout:
	var loadout := WorkerLoadout.new()
	loadout.display_name = _random_name()
	loadout.personality = _rng.randi() % Worker.PERSONALITY_LABELS.size()
	loadout.set_specialty("Generalist")
	return loadout


func _random_name() -> String:
	var names: Array[String] = WorkerSpawner.BOT_NAMES
	return names[_rng.randi() % names.size()]


## Randomly equip parts that fit `budget` pool points within the unlocked tier.
## Slots are visited in random order; some slots are left empty for variety.
func _randomize_parts(loadout: WorkerLoadout, budget: int) -> void:
	var ids: PackedStringArray = PackedStringArray()
	for _i in PartDatabase.SLOT_LAYOUT.size():
		ids.append("")
	var order: Array[int] = []
	for i in PartDatabase.SLOT_LAYOUT.size():
		order.append(i)
	order.shuffle()
	var spent: int = 0
	var tier: int = AchievementManager.unlocked_tier()
	for slot_index in order:
		# Skip some slots so randomized crews aren't always fully kitted.
		if _rng.randf() < 0.2:
			continue
		var slot: int = PartDatabase.SLOT_LAYOUT[slot_index]
		var affordable: Array[Dictionary] = []
		for part_def in PartDatabase.parts_for(slot, tier):
			if int(part_def["cost"]) <= budget - spent:
				affordable.append(part_def)
		if affordable.is_empty():
			continue
		var pick: Dictionary = affordable[_rng.randi() % affordable.size()]
		ids[slot_index] = str(pick["id"])
		spent += int(pick["cost"])
	loadout.part_ids = ids


## Reroll one worker entirely: name, personality, and a random part loadout that
## fits the budget freed up by clearing this worker's current parts.
func _randomize_worker(index: int) -> void:
	var loadout: WorkerLoadout = _loadouts[index]
	loadout.display_name = _random_name()
	loadout.personality = _rng.randi() % Worker.PERSONALITY_LABELS.size()
	var budget: int = mini(POOL_PER_WORKER, _pool_remaining() + loadout.pool_cost())
	_randomize_parts(loadout, maxi(0, budget))


# ---- UI build ---------------------------------------------------------------

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var canvas_layer := CanvasLayer.new()
	add_child(canvas_layer)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.75)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980.0, 700.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title Banner
	var title_hbox := HBoxContainer.new()
	vbox.add_child(title_hbox)
	
	var title := Label.new()
	title.text = "EMBARK WORKBENCH — CHASSIS CONFIGURATOR"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 0.97))
	title_hbox.add_child(title)

	# Integrated Upgrade Console / Dashboard Panel
	vbox.add_child(_build_command_console())
	vbox.add_child(_hsep())

	# Horizontal Selection Worker Tabs
	vbox.add_child(_build_crew_tabs())

	# Main Split Workshop View
	var workspace := HBoxContainer.new()
	workspace.add_theme_constant_override("separation", 18)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(workspace)

	# Gather active worker loadout
	_selected_worker_index = clampi(_selected_worker_index, 0, max(0, _loadouts.size() - 1))
	var active_loadout: WorkerLoadout = _loadouts[_selected_worker_index]

	# Left Workspace Column: Chassis Assembly (Body parts)
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 12)
	workspace.add_child(left_col)
	_build_chassis_assembly_section(left_col)

	# Right Workspace Column: Profile & Diagnostic Telemetry
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 12)
	workspace.add_child(right_col)
	_build_profile_section(right_col, active_loadout)
	_build_diagnostics_section(right_col, active_loadout)

	vbox.add_child(_hsep())
	vbox.add_child(_build_bottom_bar())


## Displays available points, tech tiers, crew capacity, and upgrade options.
func _build_command_console() -> Control:
	var console := PanelContainer.new()
	console.add_theme_stylebox_override("panel", _card_style())
	
	var console_margin := MarginContainer.new()
	console_margin.add_theme_constant_override("margin_left", 14)
	console_margin.add_theme_constant_override("margin_top", 10)
	console_margin.add_theme_constant_override("margin_right", 14)
	console_margin.add_theme_constant_override("margin_bottom", 10)
	console.add_child(console_margin)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_margin.add_child(grid)

	# Column 1: AP & Tech Tier
	var tier_box := VBoxContainer.new()
	tier_box.add_theme_constant_override("separation", 2)
	
	var ap_title := Label.new()
	ap_title.text = "GLOBAL ACQUISITION POWER"
	ap_title.add_theme_font_size_override("font_size", 9)
	ap_title.add_theme_color_override("font_color", Color(0.58, 0.64, 0.68))
	tier_box.add_child(ap_title)

	var ap_val := Label.new()
	ap_val.text = "%d AP  (Tech Tier: T%d)" % [AchievementManager.available_points(), AchievementManager.unlocked_tier()]
	ap_val.add_theme_font_size_override("font_size", 13)
	ap_val.add_theme_color_override("font_color", Color(0.84, 0.78, 0.46))
	tier_box.add_child(ap_val)

	var tier_cost: int = AchievementManager.next_tier_cost()
	var tier_btn := Button.new()
	tier_btn.custom_minimum_size = Vector2(0, 26)
	tier_btn.add_theme_font_size_override("font_size", 10)
	if tier_cost < 0:
		tier_btn.text = "Max Tech Tier Reached"
		tier_btn.disabled = true
	else:
		tier_btn.text = "Unlock Tech Tier T%d (%d AP)" % [AchievementManager.unlocked_tier() + 1, tier_cost]
		tier_btn.disabled = tier_cost > AchievementManager.available_points()
		tier_btn.pressed.connect(func() -> void:
			AudioManager.play_button_press()
			if AchievementManager.purchase_tier_unlock():
				_build_ui())
	tier_box.add_child(tier_btn)
	grid.add_child(tier_box)

	# Column 2: Crew Capacity & Expansion
	var slot_box := VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 2)

	var crew_title := Label.new()
	crew_title.text = "ACTIVE CHASSIS SLOTS"
	crew_title.add_theme_font_size_override("font_size", 9)
	crew_title.add_theme_color_override("font_color", Color(0.58, 0.64, 0.68))
	slot_box.add_child(crew_title)

	var crew_val := Label.new()
	crew_val.text = "%d / %d Active Worker Chassis" % [_loadouts.size(), _slot_count()]
	crew_val.add_theme_font_size_override("font_size", 13)
	crew_val.add_theme_color_override("font_color", Color(0.62, 0.78, 0.92))
	slot_box.add_child(crew_val)

	var slot_cost: int = AchievementManager.next_worker_slot_cost()
	var slot_btn := Button.new()
	slot_btn.custom_minimum_size = Vector2(0, 26)
	slot_btn.add_theme_font_size_override("font_size", 10)
	if slot_cost < 0:
		slot_btn.text = "Max Chassis Slots Operational"
		slot_btn.disabled = true
	else:
		slot_btn.text = "Commission Slot (%d AP)" % slot_cost
		slot_btn.disabled = slot_cost > AchievementManager.available_points()
		slot_btn.pressed.connect(func() -> void:
			AudioManager.play_button_press()
			if AchievementManager.purchase_worker_slot():
				_sync_loadout_count()
				_build_ui())
	slot_box.add_child(slot_btn)
	grid.add_child(slot_box)

	# Column 3: Cognitive Decoders (Personalities)
	var pers_box := VBoxContainer.new()
	pers_box.add_theme_constant_override("separation", 2)

	var pers_title := Label.new()
	pers_title.text = "COGNITIVE MATRIX DECODER"
	pers_title.add_theme_font_size_override("font_size", 9)
	pers_title.add_theme_color_override("font_color", Color(0.58, 0.64, 0.68))
	pers_box.add_child(pers_title)

	var pers_unlocked: bool = AchievementManager.personality_unlocked()
	var pers_val := Label.new()
	pers_val.text = "Manual Calibration: Active" if pers_unlocked else "Calibration Mode: Randomized"
	pers_val.add_theme_font_size_override("font_size", 13)
	pers_val.add_theme_color_override("font_color", Color(0.55, 0.85, 0.62) if pers_unlocked else Color(0.70, 0.72, 0.76))
	pers_box.add_child(pers_val)

	var pers_cost: int = AchievementManager.next_personality_unlock_cost()
	var pers_btn := Button.new()
	pers_btn.custom_minimum_size = Vector2(0, 26)
	pers_btn.add_theme_font_size_override("font_size", 10)
	if pers_unlocked or pers_cost < 0:
		pers_btn.text = "Decoder Modules Installed"
		pers_btn.disabled = true
	else:
		pers_btn.text = "Unlock Selection (%d AP)" % pers_cost
		pers_btn.disabled = pers_cost > AchievementManager.available_points()
		pers_btn.pressed.connect(func() -> void:
			AudioManager.play_button_press()
			if AchievementManager.purchase_personality_unlock():
				_build_ui())
	pers_box.add_child(pers_btn)
	grid.add_child(pers_box)

	return console


## Horizontal tabs matching the active team members.
func _build_crew_tabs() -> Control:
	var tabs_box := HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", 6)
	tabs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for i in _loadouts.size():
		var loadout: WorkerLoadout = _loadouts[i]
		var is_selected: bool = (i == _selected_worker_index)

		var tab_btn := Button.new()
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.custom_minimum_size = Vector2(120, 42)
		tab_btn.text = "%s\n[%s]" % [loadout.display_name, loadout.specialty.to_upper()]
		tab_btn.add_theme_font_size_override("font_size", 11)

		if is_selected:
			tab_btn.add_theme_stylebox_override("normal", _tab_active_style())
			tab_btn.add_theme_stylebox_override("hover", _tab_active_style())
			tab_btn.add_theme_stylebox_override("pressed", _tab_active_style())
			tab_btn.add_theme_color_override("font_color", Color(0.55, 0.85, 0.62))
		else:
			tab_btn.add_theme_stylebox_override("normal", _tab_inactive_style())
			tab_btn.add_theme_color_override("font_color", Color(0.60, 0.65, 0.68))

		tab_btn.pressed.connect(func() -> void:
			AudioManager.play_button_press()
			_selected_worker_index = i
			_build_ui())

		tabs_box.add_child(tab_btn)

	return tabs_box


## Core vs Modules grouping layout for physical equipment.
func _build_chassis_assembly_section(parent: Control) -> void:
	# Group A: Core Systems (Slots 0, 1, 2)
	var core_panel := PanelContainer.new()
	core_panel.add_theme_stylebox_override("panel", _card_style())
	parent.add_child(core_panel)

	var core_margin := MarginContainer.new()
	core_margin.add_theme_constant_override("margin_left", 12)
	core_margin.add_theme_constant_override("margin_top", 10)
	core_margin.add_theme_constant_override("margin_right", 12)
	core_margin.add_theme_constant_override("margin_bottom", 12)
	core_panel.add_child(core_margin)

	var core_vbox := VBoxContainer.new()
	core_vbox.add_theme_constant_override("separation", 6)
	core_margin.add_child(core_vbox)

	_section_label(core_vbox, "CHASSIS CORE SYSTEMS")
	for slot_idx in [0, 1, 2]:
		if slot_idx < PartDatabase.SLOT_LAYOUT.size():
			core_vbox.add_child(_build_slot_button(_selected_worker_index, slot_idx))

	# Group B: Hardware & Weapons Modules (Slots 3 to 7)
	var mods_panel := PanelContainer.new()
	mods_panel.add_theme_stylebox_override("panel", _card_style())
	parent.add_child(mods_panel)

	var mods_margin := MarginContainer.new()
	mods_margin.add_theme_constant_override("margin_left", 12)
	mods_margin.add_theme_constant_override("margin_top", 10)
	mods_margin.add_theme_constant_override("margin_right", 12)
	mods_margin.add_theme_constant_override("margin_bottom", 12)
	mods_panel.add_child(mods_margin)

	var mods_vbox := VBoxContainer.new()
	mods_vbox.add_theme_constant_override("separation", 6)
	mods_margin.add_child(mods_vbox)

	_section_label(mods_vbox, "HARDWARE & WEAPON MODULES")
	for slot_idx in range(3, PartDatabase.SLOT_LAYOUT.size()):
		mods_vbox.add_child(_build_slot_button(_selected_worker_index, slot_idx))


## Identity Card panel (Name, Personality, Specialty, Reroll)
func _build_profile_section(parent: Control, loadout: WorkerLoadout) -> void:
	var profile_panel := PanelContainer.new()
	profile_panel.add_theme_stylebox_override("panel", _card_style())
	parent.add_child(profile_panel)

	var p_margin := MarginContainer.new()
	p_margin.add_theme_constant_override("margin_left", 12)
	p_margin.add_theme_constant_override("margin_top", 10)
	p_margin.add_theme_constant_override("margin_right", 12)
	p_margin.add_theme_constant_override("margin_bottom", 12)
	profile_panel.add_child(p_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	p_margin.add_child(vbox)

	var title_hbox := HBoxContainer.new()
	vbox.add_child(title_hbox)
	_section_label(title_hbox, "IDENTITY MATRIX")

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(spacer)

	# Inline direct reroll of this specific unit chassis
	var reroll := Button.new()
	reroll.text = "Reroll Unit"
	reroll.add_theme_font_size_override("font_size", 10)
	reroll.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		_randomize_worker(_selected_worker_index)
		_build_ui())
	title_hbox.add_child(reroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	# Name row
	var name_lbl := Label.new()
	name_lbl.text = "Chassis Designation:"
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.72))
	grid.add_child(name_lbl)

	var name_edit := LineEdit.new()
	name_edit.text = loadout.display_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 12)
	name_edit.text_submitted.connect(func(t: String) -> void:
		loadout.display_name = t.strip_edges() if not t.strip_edges().is_empty() else loadout.display_name
		_build_ui())
	name_edit.focus_exited.connect(func() -> void:
		var t: String = name_edit.text.strip_edges()
		if not t.is_empty():
			loadout.display_name = t)
	grid.add_child(name_edit)

	# Personality row
	var pers_lbl := Label.new()
	pers_lbl.text = "Cognitive Temper:"
	pers_lbl.add_theme_font_size_override("font_size", 11)
	pers_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.72))
	grid.add_child(pers_lbl)

	if AchievementManager.personality_unlocked():
		var pers_opt := OptionButton.new()
		pers_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for p in Worker.PERSONALITY_LABELS.size():
			pers_opt.add_item(Worker.PERSONALITY_LABELS[p], p)
		pers_opt.select(clampi(loadout.personality, 0, Worker.PERSONALITY_LABELS.size() - 1))
		pers_opt.item_selected.connect(func(id: int) -> void:
			loadout.personality = id
			_build_ui())
		grid.add_child(pers_opt)
	else:
		var pers_val := Label.new()
		pers_val.text = Worker.PERSONALITY_LABELS[clampi(loadout.personality, 0, Worker.PERSONALITY_LABELS.size() - 1)]
		pers_val.add_theme_font_size_override("font_size", 12)
		pers_val.add_theme_color_override("font_color", Color(0.72, 0.62, 0.42))
		pers_val.tooltip_text = "Unlock Selection above to choose manually"
		grid.add_child(pers_val)

	# Specialty Role row
	var role_lbl := Label.new()
	role_lbl.text = "Operational Role:"
	role_lbl.add_theme_font_size_override("font_size", 11)
	role_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.72))
	grid.add_child(role_lbl)

	var role_opt := OptionButton.new()
	role_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_spec: int = 0
	for s in WorkerLoadout.SPECIALTIES.size():
		var spec_name: String = str(WorkerLoadout.SPECIALTIES[s]["name"])
		role_opt.add_item(spec_name, s)
		role_opt.set_item_tooltip(s, WorkerLoadout.role_desc(spec_name))
		if spec_name == loadout.specialty:
			selected_spec = s
	role_opt.select(selected_spec)
	role_opt.item_selected.connect(func(id: int) -> void:
		loadout.set_specialty(str(WorkerLoadout.SPECIALTIES[id]["name"]))
		_build_ui())
	grid.add_child(role_opt)


## Detailed panel showing graphical stats and efficiency meters.
func _build_diagnostics_section(parent: Control, loadout: WorkerLoadout) -> void:
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _card_style())
	parent.add_child(stats_panel)

	var s_margin := MarginContainer.new()
	s_margin.add_theme_constant_override("margin_left", 12)
	s_margin.add_theme_constant_override("margin_top", 10)
	s_margin.add_theme_constant_override("margin_right", 12)
	s_margin.add_theme_constant_override("margin_bottom", 12)
	stats_panel.add_child(s_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	s_margin.add_child(vbox)

	_section_label(vbox, "DIAGNOSTIC TELEMETRY")

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	var stats: Dictionary = loadout.derive()
	for entry in STAT_DISPLAY:
		var key: String = str(entry["key"])
		var fmt: String = str(entry["fmt"])
		var raw_val: float = _get_raw_stat_value(stats, key)
		var text_val: String = _format_stat(stats, key, fmt)

		# Col 1: Label
		var label := Label.new()
		label.text = str(entry["label"])
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.72))
		grid.add_child(label)

		# Col 2: Readout
		var val_lbl := Label.new()
		val_lbl.text = text_val
		val_lbl.add_theme_font_size_override("font_size", 11)
		val_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 0.96))
		grid.add_child(val_lbl)

		# Col 3: Visual Pip Progress Meter
		grid.add_child(_build_pip_bar(key, raw_val))


## Helper method to compute normalized scaling values for physical stats.
func _get_raw_stat_value(s: Dictionary, key: String) -> float:
	if key == "bash":
		var b_min: float = float(s.get("bash_min", 2.0))
		var b_max: float = float(s.get("bash_max", 5.0))
		return (b_min + b_max) / 2.0
	return float(s.get(key, 0.0))


## Generates a 10-segment diagnostic indicator representing current efficiency tiers.
func _build_pip_bar(key: String, value: float) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var total_pips: int = 10
	var percent: float = 0.0

	# Normalizes scaling metrics based on functional operational envelopes
	match key:
		"move_speed": percent = value / 60.0
		"max_hp": percent = value / 120.0
		"armor": percent = value / 10.0
		"bash": percent = value / 15.0
		"carry": percent = value / 6.0
		"sight": percent = value / 5.0
		"work_speed", "mine_speed", "build_speed", "wisdom", "energy_recharge", "energy_drain":
			percent = value / 2.0
		"dodge": percent = value / 0.50
		"mood_baseline": percent = value / 120.0
		_: percent = value / 100.0

	var active_pips: int = clampi(int(roundf(percent * total_pips)), 0, total_pips)
	var active_color := Color(0.55, 0.85, 0.62) # Operational Green
	if key in ["energy_drain"]:
		active_color = Color(1.0, 0.5, 0.4) # Thermal alert red
	elif key in ["max_hp", "armor"]:
		active_color = Color(0.62, 0.78, 0.92) # Protective blue

	for i in total_pips:
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(4, 8)
		if i < active_pips:
			rect.color = active_color
		else:
			rect.color = Color(0.2, 0.22, 0.25, 0.4) # Unused capacity
		box.add_child(rect)

	return box


func _format_stat(s: Dictionary, key: String, fmt: String) -> String:
	match fmt:
		"int":
			return "%d" % int(roundf(float(s.get(key, 0.0))))
		"plus":
			return "+%d" % int(roundf(float(s.get(key, 0.0))))
		"mult":
			return "x%.2f" % float(s.get(key, 1.0))
		"pct":
			return "%d%%" % int(roundf(float(s.get(key, 0.0)) * 100.0))
		"range":
			return "%d-%d" % [int(roundf(float(s.get("bash_min", 0.0)))), int(roundf(float(s.get("bash_max", 0.0))))]
	return "-"


func _build_slot_button(worker_index: int, slot_index: int) -> Control:
	var loadout: WorkerLoadout = _loadouts[worker_index]
	var slot: int = PartDatabase.SLOT_LAYOUT[slot_index]
	var part_id: StringName = StringName(loadout.part_ids[slot_index])
	var part_def: Dictionary = PartDatabase.part(part_id)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 11)

	if part_def.is_empty():
		btn.text = "  %s:  — empty" % PartDatabase.slot_label(slot)
		btn.tooltip_text = "Install a %s module" % PartDatabase.slot_label(slot)
		btn.add_theme_color_override("font_color", Color(0.48, 0.54, 0.58))
	else:
		btn.text = "  %s:  %s  (T%d · %d pts)" % [
			PartDatabase.slot_label(slot), str(part_def["name"]), int(part_def["tier"]), int(part_def["cost"])]
		btn.tooltip_text = "%s\n%s" % [str(part_def["desc"]), _mods_summary(part_def)]
		btn.add_theme_color_override("font_color", Color(0.55, 0.85, 0.62)) # Highlight filled modules
	
	btn.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		_open_part_picker(worker_index, slot_index))
	return btn


func _build_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(110, 36)
	back.pressed.connect(_on_cancel)
	back.pressed.connect(AudioManager.play_button_press)
	bar.add_child(back)

	# Active resource pool progress tracking bar
	var telemetry_box := HBoxContainer.new()
	telemetry_box.add_theme_constant_override("separation", 8)
	telemetry_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(telemetry_box)

	var remaining: int = _pool_remaining()
	var pool_color: Color = Color(0.55, 0.85, 0.62) if remaining >= 0 else Color(1.0, 0.5, 0.4)

	var pool_lbl := Label.new()
	pool_lbl.text = "ENERGY LOADOUT POOL:"
	pool_lbl.add_theme_font_size_override("font_size", 10)
	pool_lbl.add_theme_color_override("font_color", Color(0.58, 0.64, 0.68))
	pool_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	telemetry_box.add_child(pool_lbl)

	var pool_val := Label.new()
	pool_val.text = "%d / %d" % [remaining, _pool_total()]
	pool_val.add_theme_font_size_override("font_size", 13)
	pool_val.add_theme_color_override("font_color", pool_color)
	pool_val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	telemetry_box.add_child(pool_val)

	var pool_bar := ProgressBar.new()
	pool_bar.min_value = 0
	pool_bar.max_value = _pool_total()
	pool_bar.value = _pool_used()
	pool_bar.show_percentage = false
	pool_bar.custom_minimum_size = Vector2(140, 10)
	pool_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.12, 0.14, 0.16, 1.0)
	sb_bg.corner_radius_top_left = 3
	sb_bg.corner_radius_top_right = 3
	sb_bg.corner_radius_bottom_left = 3
	sb_bg.corner_radius_bottom_right = 3
	pool_bar.add_theme_stylebox_override("background", sb_bg)

	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = pool_color
	sb_fg.corner_radius_top_left = 3
	sb_fg.corner_radius_top_right = 3
	sb_fg.corner_radius_bottom_left = 3
	sb_fg.corner_radius_bottom_right = 3
	pool_bar.add_theme_stylebox_override("fill", sb_fg)
	telemetry_box.add_child(pool_bar)

	var rand_all := Button.new()
	rand_all.text = "Randomize All"
	rand_all.tooltip_text = "Reroll all units completely."
	rand_all.custom_minimum_size = Vector2(130, 36)
	rand_all.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		for i in _loadouts.size():
			_loadouts[i] = _random_loadout()
			_randomize_worker(i)
		_build_ui())
	bar.add_child(rand_all)

	var proceed := Button.new()
	proceed.text = "Proceed"
	proceed.custom_minimum_size = Vector2(130, 36)
	proceed.disabled = _pool_remaining() < 0
	proceed.pressed.connect(_on_proceed)
	proceed.pressed.connect(AudioManager.play_button_press)
	bar.add_child(proceed)

	return bar


# ---- part picker popup ------------------------------------------------------

func _open_part_picker(worker_index: int, slot_index: int) -> void:
	if has_node("PartPicker"):
		get_node("PartPicker").queue_free()

	var loadout: WorkerLoadout = _loadouts[worker_index]
	var slot: int = PartDatabase.SLOT_LAYOUT[slot_index]
	var current_id: StringName = StringName(loadout.part_ids[slot_index])
	var current_cost: int = 0
	var current_def: Dictionary = PartDatabase.part(current_id)
	if not current_def.is_empty():
		current_cost = int(current_def["cost"])

	var layer := CanvasLayer.new()
	layer.name = "PartPicker"
	layer.layer = 2
	add_child(layer)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.theme = UiStyle.button_theme()
	layer.add_child(overlay)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			layer.queue_free())
	overlay.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 540)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var head := Label.new()
	head.text = "%s — Choose a part  (Pool left: %d)" % [PartDatabase.slot_label(slot), _pool_remaining()]
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(0.95, 0.97, 0.96))
	vbox.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 420)
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(_build_picker_row(worker_index, slot_index, {}, current_id, current_cost, layer))

	for part_def in PartDatabase.parts_for(slot, AchievementManager.unlocked_tier()):
		list.add_child(_build_picker_row(worker_index, slot_index, part_def, current_id, current_cost, layer))

	var close := Button.new()
	close.text = "Cancel"
	close.custom_minimum_size = Vector2(120, 36)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		layer.queue_free())
	vbox.add_child(close)


func _build_picker_row(
	worker_index: int, slot_index: int, part_def: Dictionary,
	current_id: StringName, current_cost: int, layer: CanvasLayer,
) -> Control:
	var is_empty_option: bool = part_def.is_empty()
	var part_id: StringName = current_id if is_empty_option else StringName(part_def["id"])
	var cost: int = 0 if is_empty_option else int(part_def["cost"])
	var affordable: bool = is_empty_option or (_pool_remaining() + current_cost >= cost)
	var is_current: bool = (not is_empty_option) and StringName(part_def["id"]) == current_id

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _card_style())

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_top", 6)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_bottom", 6)
	row.add_child(inner)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	inner.add_child(hbox)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 1)
	hbox.add_child(text_col)

	var name_lbl := Label.new()
	if is_empty_option:
		name_lbl.text = "— Empty Slot (no part)"
	else:
		name_lbl.text = "%s   T%d   ·   %d pts" % [str(part_def["name"]), int(part_def["tier"]), cost]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color",
		Color(0.92, 0.96, 0.94) if affordable else Color(0.55, 0.42, 0.42))
	text_col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "clears this slot" if is_empty_option else "%s  [%s]" % [str(part_def["desc"]), _mods_summary(part_def)]
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.56, 0.62, 0.66))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_lbl)

	var action := Button.new()
	action.custom_minimum_size = Vector2(96, 32)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_empty_option:
		action.text = "Clear"
		action.disabled = current_id == &""
	elif is_current:
		action.text = "Equipped"
		action.disabled = true
	else:
		action.text = "Equip"
		action.disabled = not affordable
	action.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		var loadout: WorkerLoadout = _loadouts[worker_index]
		var ids: PackedStringArray = loadout.part_ids
		ids[slot_index] = "" if is_empty_option else str(part_def["id"])
		loadout.part_ids = ids
		layer.queue_free()
		_build_ui())
	hbox.add_child(action)

	return row


# ---- helpers ----------------------------------------------------------------

func _section_label(parent: Control, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.84, 0.78, 0.46))
	parent.add_child(label)


func _mods_summary(part_def: Dictionary) -> String:
	var mods: Dictionary = part_def["mods"] as Dictionary
	var parts: Array[String] = []
	for key in mods:
		var v: float = float(mods[key])
		var sign_str: String = "+" if v >= 0 else ""
		if absf(v - roundf(v)) < 0.001:
			parts.append("%s %s%d" % [str(key), sign_str, int(v)])
		else:
			parts.append("%s %s%.2f" % [str(key), sign_str, v])
	return ", ".join(parts)


func _on_cancel() -> void:
	embark_cancelled.emit()
	queue_free()


func _on_proceed() -> void:
	if _pool_remaining() < 0:
		return
	var out: Array = []
	for loadout in _loadouts:
		out.append(loadout)
	embark_confirmed.emit(out)
	queue_free()


func _hsep() -> Control:
	var sep := HSeparator.new()
	return sep


static func _card_style() -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.94)
	style.border_color = Color(0.24, 0.28, 0.32, 0.50)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


static func _tab_active_style() -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.18, 1.0)
	style.border_color = Color(0.55, 0.85, 0.62, 1.0) # Active line
	style.set_border_width_all(1)
	style.border_width_bottom = 0
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	return style


static func _tab_inactive_style() -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.90)
	style.border_color = Color(0.18, 0.20, 0.22, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	return style


static func _panel_style() -> StyleBox:
	const PANEL_PATH := "res://resources/ui/panels/selection_panel.png"
	if ResourceLoader.exists(PANEL_PATH):
		var tex: Texture2D = load(PANEL_PATH) as Texture2D
		if tex != null:
			var tex_style := StyleBoxTexture.new()
			tex_style.texture = tex
			tex_style.texture_margin_left = 16.0
			tex_style.texture_margin_top = 16.0
			tex_style.texture_margin_right = 16.0
			tex_style.texture_margin_bottom = 16.0
			return tex_style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.075, 0.085, 0.98)
	style.border_color = Color(0.32, 0.38, 0.42, 0.70)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style
