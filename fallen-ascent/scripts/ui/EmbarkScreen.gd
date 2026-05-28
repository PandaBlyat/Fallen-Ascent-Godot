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
	{"key": "move_speed", "label": "Move", "fmt": "int"},
	{"key": "max_hp", "label": "Max HP", "fmt": "int"},
	{"key": "armor", "label": "Armor", "fmt": "int"},
	{"key": "bash", "label": "Bash", "fmt": "range"},
	{"key": "carry", "label": "Carry", "fmt": "int"},
	{"key": "sight", "label": "Sight", "fmt": "plus"},
	{"key": "work_speed", "label": "Work", "fmt": "mult"},
	{"key": "mine_speed", "label": "Mining", "fmt": "mult"},
	{"key": "build_speed", "label": "Building", "fmt": "mult"},
	{"key": "wisdom", "label": "Research", "fmt": "mult"},
	{"key": "energy_recharge", "label": "Recharge", "fmt": "mult"},
	{"key": "energy_drain", "label": "Drain", "fmt": "mult"},
	{"key": "dodge", "label": "Dodge", "fmt": "pct"},
	{"key": "mood_baseline", "label": "Mood Base", "fmt": "int"},
]

var _loadouts: Array[WorkerLoadout] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# Skin the embark buttons with the shared worker-card texture (this screen is
	# added under Main, but its own CanvasLayers can break theme inheritance, so
	# set it explicitly here).
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
	dimmer.color = Color(0, 0, 0, 0.66)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(940.0, 680.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "EMBARK — ASSEMBLE YOUR CREW"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 0.97))
	vbox.add_child(title)

	vbox.add_child(_build_resource_bar())
	vbox.add_child(_build_store_bar())
	vbox.add_child(_hsep())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)

	for i in _loadouts.size():
		cards.add_child(_build_worker_card(i))

	vbox.add_child(_build_bottom_bar())


func _build_resource_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 22)

	bar.add_child(_stat_pill("Achievement Points", "%d" % AchievementManager.available_points(), Color(0.84, 0.78, 0.46)))

	var remaining: int = _pool_remaining()
	var pool_color: Color = Color(0.55, 0.85, 0.62) if remaining >= 0 else Color(1.0, 0.5, 0.4)
	bar.add_child(_stat_pill("Part Pool", "%d / %d" % [remaining, _pool_total()], pool_color))

	bar.add_child(_stat_pill("Unlocked Tier", "T%d" % AchievementManager.unlocked_tier(), Color(0.62, 0.78, 0.92)))

	var pers_unlocked: bool = AchievementManager.personality_unlocked()
	bar.add_child(_stat_pill("Personality Choice",
		"Unlocked" if pers_unlocked else "Random",
		Color(0.55, 0.85, 0.62) if pers_unlocked else Color(0.70, 0.72, 0.76)))

	return bar


## A small "LABEL value" readout used in the resource bar.
func _stat_pill(key: String, value: String, value_color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var key_lbl := Label.new()
	key_lbl.text = key.to_upper()
	key_lbl.add_theme_font_size_override("font_size", 9)
	key_lbl.add_theme_color_override("font_color", Color(0.58, 0.64, 0.68))
	box.add_child(key_lbl)
	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.add_theme_font_size_override("font_size", 15)
	val_lbl.add_theme_color_override("font_color", value_color)
	box.add_child(val_lbl)
	return box


func _build_store_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)

	var tier_cost: int = AchievementManager.next_tier_cost()
	var tier_btn := Button.new()
	if tier_cost < 0:
		tier_btn.text = "All Tiers Unlocked"
		tier_btn.disabled = true
	else:
		tier_btn.text = "Unlock Tier %d  (%d AP)" % [AchievementManager.unlocked_tier() + 1, tier_cost]
		tier_btn.tooltip_text = "Permanently unlock higher-tier parts for all future embarks."
		tier_btn.disabled = tier_cost > AchievementManager.available_points()
		tier_btn.pressed.connect(func() -> void:
			AudioManager.play_button_press()
			if AchievementManager.purchase_tier_unlock():
				_build_ui())
	bar.add_child(tier_btn)

	var slot_cost: int = AchievementManager.next_worker_slot_cost()
	var slot_btn := Button.new()
	if slot_cost < 0:
		slot_btn.text = "Max Crew Size"
		slot_btn.disabled = true
	else:
		slot_btn.text = "Add Worker  (%d AP)" % slot_cost
		slot_btn.tooltip_text = "Permanently add a starting worker slot (and more part pool)."
		slot_btn.disabled = slot_cost > AchievementManager.available_points()
		slot_btn.pressed.connect(func() -> void:
			AudioManager.play_button_press()
			if AchievementManager.purchase_worker_slot():
				_sync_loadout_count()
				_build_ui())
	bar.add_child(slot_btn)

	var pers_cost: int = AchievementManager.next_personality_unlock_cost()
	if pers_cost >= 0:
		var pers_btn := Button.new()
		pers_btn.text = "Unlock Personality Choice  (%d AP)" % pers_cost
		pers_btn.tooltip_text = "Permanently allow hand-picking each worker's personality.\nUntil then, personalities are randomized (reroll with Randomize)."
		pers_btn.disabled = pers_cost > AchievementManager.available_points()
		pers_btn.pressed.connect(func() -> void:
			AudioManager.play_button_press()
			if AchievementManager.purchase_personality_unlock():
				_build_ui())
		bar.add_child(pers_btn)

	return bar


func _build_worker_card(index: int) -> Control:
	var loadout: WorkerLoadout = _loadouts[index]

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 14)
	inner.add_theme_constant_override("margin_top", 11)
	inner.add_theme_constant_override("margin_right", 14)
	inner.add_theme_constant_override("margin_bottom", 12)
	card.add_child(inner)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	inner.add_child(col)

	col.add_child(_build_card_header(index, loadout))
	col.add_child(_build_card_subheader(loadout))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	col.add_child(columns)

	var parts_col := VBoxContainer.new()
	parts_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_col.add_theme_constant_override("separation", 5)
	columns.add_child(parts_col)
	_build_parts_section(parts_col, index)

	var stats_col := VBoxContainer.new()
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_col.add_theme_constant_override("separation", 5)
	columns.add_child(stats_col)
	_build_stats_section(stats_col, loadout)

	return card


## Header row: status dot, editable name, per-worker randomize.
func _build_card_header(index: int, loadout: WorkerLoadout) -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.color = Color(0.38, 0.80, 0.58, 1.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(dot)

	var name_edit := LineEdit.new()
	name_edit.text = loadout.display_name
	name_edit.custom_minimum_size = Vector2(180, 0)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.tooltip_text = "Click to rename this worker"
	name_edit.text_submitted.connect(func(t: String) -> void:
		loadout.display_name = t.strip_edges() if not t.strip_edges().is_empty() else loadout.display_name)
	name_edit.focus_exited.connect(func() -> void:
		var t: String = name_edit.text.strip_edges()
		if not t.is_empty():
			loadout.display_name = t)
	header.add_child(name_edit)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var randomize_btn := Button.new()
	randomize_btn.text = "Randomize"
	randomize_btn.tooltip_text = "Reroll this worker's name, personality, and a random part loadout."
	randomize_btn.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		_randomize_worker(index)
		_build_ui())
	header.add_child(randomize_btn)

	return header


## Sub-header row: personality (label or, if unlocked, a dropdown) + role picker.
func _build_card_subheader(loadout: WorkerLoadout) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var pers_lbl := Label.new()
	pers_lbl.text = "Personality"
	pers_lbl.add_theme_font_size_override("font_size", 11)
	pers_lbl.add_theme_color_override("font_color", Color(0.62, 0.70, 0.74))
	row.add_child(pers_lbl)

	if AchievementManager.personality_unlocked():
		var pers := OptionButton.new()
		for p in Worker.PERSONALITY_LABELS.size():
			pers.add_item(Worker.PERSONALITY_LABELS[p], p)
		pers.select(clampi(loadout.personality, 0, Worker.PERSONALITY_LABELS.size() - 1))
		pers.item_selected.connect(func(id: int) -> void:
			loadout.personality = id
			_build_ui())
		row.add_child(pers)
	else:
		var pers_value := Label.new()
		pers_value.text = Worker.PERSONALITY_LABELS[clampi(loadout.personality, 0, Worker.PERSONALITY_LABELS.size() - 1)]
		pers_value.add_theme_font_size_override("font_size", 14)
		pers_value.add_theme_color_override("font_color", Color(0.72, 0.62, 0.42))
		pers_value.tooltip_text = "Personality is randomized. Reroll with Randomize, or buy manual choice in the store above."
		pers_value.custom_minimum_size = Vector2(120, 0)
		row.add_child(pers_value)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var spec_lbl := Label.new()
	spec_lbl.text = "Role"
	spec_lbl.add_theme_font_size_override("font_size", 11)
	spec_lbl.add_theme_color_override("font_color", Color(0.62, 0.70, 0.74))
	row.add_child(spec_lbl)

	var spec := OptionButton.new()
	var selected_spec: int = 0
	for s in WorkerLoadout.SPECIALTIES.size():
		var spec_name: String = str(WorkerLoadout.SPECIALTIES[s]["name"])
		spec.add_item(spec_name, s)
		spec.set_item_tooltip(s, WorkerLoadout.role_desc(spec_name))
		if spec_name == loadout.specialty:
			selected_spec = s
	spec.select(selected_spec)
	spec.tooltip_text = WorkerLoadout.role_desc(loadout.specialty)
	spec.item_selected.connect(func(id: int) -> void:
		loadout.set_specialty(str(WorkerLoadout.SPECIALTIES[id]["name"]))
		_build_ui())
	row.add_child(spec)

	return row


func _build_parts_section(parent: Control, index: int) -> void:
	_section_label(parent, "BODY PARTS")
	var slots := VBoxContainer.new()
	slots.add_theme_constant_override("separation", 4)
	parent.add_child(slots)
	for slot_index in PartDatabase.SLOT_LAYOUT.size():
		slots.add_child(_build_slot_button(index, slot_index))


## A compact two-column readout of every derived stat, including defaults, so the
## player always sees the full picture of a worker even with no parts equipped.
func _build_stats_section(parent: Control, loadout: WorkerLoadout) -> void:
	_section_label(parent, "STATS")
	var s: Dictionary = loadout.derive()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	for entry in STAT_DISPLAY:
		var key: String = str(entry["key"])
		var fmt: String = str(entry["fmt"])
		var value_text: String = _format_stat(s, key, fmt)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		grid.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = str(entry["label"])
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.72))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = value_text
		val_lbl.add_theme_font_size_override("font_size", 11)
		val_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 0.96))
		row.add_child(val_lbl)


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
	btn.custom_minimum_size = Vector2(0, 34)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 11)
	if part_def.is_empty():
		btn.text = "%s:  — empty" % PartDatabase.slot_label(slot)
		btn.tooltip_text = "Choose a %s part" % PartDatabase.slot_label(slot)
	else:
		btn.text = "%s:  %s  (T%d · %d pts)" % [
			PartDatabase.slot_label(slot), str(part_def["name"]), int(part_def["tier"]), int(part_def["cost"])]
		btn.tooltip_text = "%s\n%s" % [str(part_def["desc"]), _mods_summary(part_def)]
	btn.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		_open_part_picker(worker_index, slot_index))
	return btn


func _build_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(110, 38)
	back.pressed.connect(_on_cancel)
	back.pressed.connect(AudioManager.play_button_press)
	bar.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var randomize_btn := Button.new()
	randomize_btn.text = "Randomize All"
	randomize_btn.tooltip_text = "Reroll every worker individually (name, personality, parts)."
	randomize_btn.custom_minimum_size = Vector2(160, 38)
	randomize_btn.pressed.connect(func() -> void:
		AudioManager.play_button_press()
		for i in _loadouts.size():
			_loadouts[i] = _random_loadout()
			_randomize_worker(i)
		_build_ui())
	bar.add_child(randomize_btn)

	var proceed := Button.new()
	proceed.text = "Proceed"
	proceed.custom_minimum_size = Vector2(150, 38)
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

	# Own CanvasLayer above the main panel's layer so the picker draws on top.
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
	head.text = "%s — choose a part  (pool left: %d)" % [PartDatabase.slot_label(slot), _pool_remaining()]
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

	# "Empty" option to clear the slot.
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
	# Affordability: swapping in `cost` while refunding the slot's current cost.
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
	style.bg_color = Color(0.08, 0.10, 0.12, 0.92)
	style.border_color = Color(0.28, 0.34, 0.38, 0.55)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
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
	style.bg_color = Color(0.06, 0.075, 0.085, 0.96)
	style.border_color = Color(0.32, 0.38, 0.42, 0.7)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style
