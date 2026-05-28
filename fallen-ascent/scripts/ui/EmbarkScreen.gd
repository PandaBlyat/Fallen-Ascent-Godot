extends Control
##
## Embark customization screen shown before the seed/size dialog.
## Players can review and randomize the starting workers by clicking them.
## For now, workers are cosmetic only — no mechanical effect yet.
## Future: customize limbs, skills, personality buffs/debuffs.
##

signal embark_confirmed(workers: Array)
signal embark_cancelled

const MAX_STARTING_WORKERS: int = 6
const DEFAULT_STARTING_WORKERS: int = 3

const WORKER_NAMES: Array[String] = [
	"UNIT-7", "AXIOM", "FORGE", "NEXUS", "CIPHER",
	"VANTA", "PRISM", "STRIDER", "ECHO", "RELIC",
	"DREG", "FLUX", "COBALT", "THORN", "SERENE",
	"HAVEN", "PULSE", "GRAFT", "MIRE", "HERALD",
]

const TRAITS: Array[Dictionary] = [
	{"name": "Resilient",     "desc": "Takes longer to deteriorate under stress."},
	{"name": "Efficient",     "desc": "Slightly faster at completing tasks."},
	{"name": "Curious",       "desc": "Gains wisdom faster during downtime."},
	{"name": "Paranoid",      "desc": "Keeps watch longer — better at spotting threats."},
	{"name": "Melancholic",   "desc": "Lower baseline mood, harder to satisfy."},
	{"name": "Social",        "desc": "Mood recovers faster when chatting with others."},
	{"name": "Reclusive",     "desc": "Mood drains faster when idle near others."},
	{"name": "Industrious",   "desc": "Higher work endurance before needing rest."},
	{"name": "Fragile",       "desc": "Condition decays faster while moving."},
	{"name": "Nimble",        "desc": "Slightly faster movement speed."},
	{"name": "Stubborn",      "desc": "Ignores non-critical damage — good and bad."},
	{"name": "Methodical",    "desc": "Slightly slower but rarely makes errors."},
]

const ROLES: Array[String] = [
	"Miner", "Builder", "Scavenger", "Scout", "Technician",
]

var _worker_entries: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_worker_entries.clear()
	for i in DEFAULT_STARTING_WORKERS:
		_worker_entries.append(_random_worker())
	_build_ui()


## Returns a fresh randomized worker descriptor dict.
func _random_worker() -> Dictionary:
	return {
		"name": WORKER_NAMES[_rng.randi() % WORKER_NAMES.size()],
		"role": ROLES[_rng.randi() % ROLES.size()],
		"trait": TRAITS[_rng.randi() % TRAITS.size()],
	}


func _build_ui() -> void:
	# Clear any previous build
	for child in get_children():
		child.queue_free()

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Wrapping in a CanvasLayer guarantees viewport centering regardless of parent constraints
	var canvas_layer := CanvasLayer.new()
	add_child(canvas_layer)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.60)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dimmer)

	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas_layer.add_child(center_container)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680.0, 520.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center_container.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Embark — Starting Crew"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 0.97))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Review your starting workers. Click on any worker to randomize them."
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.70, 0.74))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)

	# Worker cards
	var cards_box := VBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 6)
	vbox.add_child(cards_box)

	for i in _worker_entries.size():
		cards_box.add_child(_build_worker_card(i))

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Bottom row
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom)

	var cancel_btn := Button.new()
	cancel_btn.text = "Back"
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	cancel_btn.pressed.connect(_on_cancel)
	cancel_btn.pressed.connect(AudioManager.play_button_press)
	bottom.add_child(cancel_btn)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer2)

	var proceed_btn := Button.new()
	proceed_btn.text = "Proceed"
	proceed_btn.custom_minimum_size = Vector2(140, 36)
	proceed_btn.pressed.connect(_on_proceed)
	proceed_btn.pressed.connect(AudioManager.play_button_press)
	bottom.add_child(proceed_btn)


func _build_worker_card(index: int) -> Control:
	var entry: Dictionary = _worker_entries[index]

	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.10, 0.12, 0.92)
	card_style.border_color = Color(0.28, 0.34, 0.38, 0.55)
	card_style.set_border_width_all(1)
	card_style.corner_radius_top_left = 4
	card_style.corner_radius_top_right = 4
	card_style.corner_radius_bottom_left = 4
	card_style.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", card_style)

	# Card interactivity settings
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "Click to randomize this worker"

	# Highlight styling on hover
	card.mouse_entered.connect(func():
		card_style.bg_color = Color(0.12, 0.16, 0.19, 0.95)
		card_style.border_color = Color(0.38, 0.44, 0.48, 0.8)
	)
	card.mouse_exited.connect(func():
		card_style.bg_color = Color(0.08, 0.10, 0.12, 0.92)
		card_style.border_color = Color(0.28, 0.34, 0.38, 0.55)
	)

	# Click input detection
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			AudioManager.play_button_press()
			_on_reroll_worker(index)
	)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS

	var inner_margin := MarginContainer.new()
	inner_margin.add_theme_constant_override("margin_left", 10)
	inner_margin.add_theme_constant_override("margin_top", 7)
	inner_margin.add_theme_constant_override("margin_right", 10)
	inner_margin.add_theme_constant_override("margin_bottom", 7)
	inner_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	inner_margin.add_child(hbox)
	card.add_child(inner_margin)

	# Worker dot/icon placeholder
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.color = Color(0.38, 0.80, 0.58, 1.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(dot)

	# Name + role
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 2)
	name_col.custom_minimum_size = Vector2(110, 0)
	name_col.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(name_col)

	var name_label := Label.new()
	name_label.text = str(entry["name"])
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.94))
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_col.add_child(name_label)

	var role_label := Label.new()
	role_label.text = str(entry["role"])
	role_label.add_theme_font_size_override("font_size", 10)
	role_label.add_theme_color_override("font_color", Color(0.56, 0.70, 0.78))
	role_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_col.add_child(role_label)

	# Trait
	var trait_col := VBoxContainer.new()
	trait_col.add_theme_constant_override("separation", 2)
	trait_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trait_col.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(trait_col)

	var trait_data: Dictionary = entry["trait"] as Dictionary
	var trait_name := Label.new()
	trait_name.text = "Trait: " + str(trait_data["name"])
	trait_name.add_theme_font_size_override("font_size", 11)
	trait_name.add_theme_color_override("font_color", Color(0.84, 0.78, 0.52))
	trait_name.mouse_filter = Control.MOUSE_FILTER_PASS
	trait_col.add_child(trait_name)

	var trait_desc := Label.new()
	trait_desc.text = str(trait_data["desc"])
	trait_desc.add_theme_font_size_override("font_size", 10)
	trait_desc.add_theme_color_override("font_color", Color(0.56, 0.62, 0.65))
	trait_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trait_desc.mouse_filter = Control.MOUSE_FILTER_PASS
	trait_col.add_child(trait_desc)

	return card


func _on_randomize_all() -> void:
	_worker_entries.clear()
	for i in DEFAULT_STARTING_WORKERS:
		_worker_entries.append(_random_worker())
	_build_ui()


func _on_reroll_worker(index: int) -> void:
	if index < 0 or index >= _worker_entries.size():
		return
	_worker_entries[index] = _random_worker()
	_build_ui()


func _on_cancel() -> void:
	embark_cancelled.emit()
	queue_free()


func _on_proceed() -> void:
	embark_confirmed.emit(_worker_entries.duplicate(true))
	queue_free()


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
