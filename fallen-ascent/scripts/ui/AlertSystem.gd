extends CanvasLayer
##
## Right-aligned alert panel system.
## Alerts slide in from the right edge. Left-click expands extra info.
## Right-click dismisses an alert immediately.
##
## Receives events from EventBus signals and from ColonySite's hostile tracker.
##

const MAX_ALERTS: int = 8
const ALERT_FADE_IN_SEC: float = 0.25
const ALERT_LIFETIME_SEC: float = 30.0
const CARD_WIDTH: float = 280.0
const CARD_MIN_HEIGHT: float = 44.0
const CARD_PADDING: float = 8.0
const CARD_SPACING: float = 6.0
const FONT: Font = preload("res://resources/Orbitron-VariableFont_wght.ttf")
const FONT_SIZE_TITLE: int = 11
const FONT_SIZE_BODY: int = 10

## Alert kinds drive icon colour.
enum Kind { INFO, WARNING, DANGER, COMBAT }

const KIND_COLORS: Array[Color] = [
	Color(0.45, 0.75, 0.95, 1.0),  ## INFO  — blue
	Color(0.98, 0.75, 0.25, 1.0),  ## WARNING — amber
	Color(0.95, 0.30, 0.28, 1.0),  ## DANGER — red
	Color(0.95, 0.28, 0.28, 1.0),  ## COMBAT — red
]

## De-duplication: tracks (title+body) hashes of alerts emitted within a short window.
const DEDUP_WINDOW_SEC: float = 5.0

var _container: VBoxContainer
var _cards: Array[Control] = []
var _camera: Camera2D = null
var _dedup: Dictionary = {}   ## hash -> float (time emitted)

## Outlet alert: only fire once until count returns to 0 and back up.
var _outlet_alert_sent: bool = false
## Hostile spot de-dup: hostile node -> float timestamp.
var _hostile_spotted_times: Dictionary = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_container = VBoxContainer.new()
	_container.anchor_left = 1.0
	_container.anchor_right = 1.0
	_container.anchor_top = 0.0
	_container.anchor_bottom = 0.0
	_container.offset_left = -(CARD_WIDTH + 12.0)
	_container.offset_right = -8.0
	_container.offset_top = 12.0
	_container.add_theme_constant_override("separation", int(CARD_SPACING))
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_container)

	EventBus.worker_entered_combat.connect(_on_worker_attacked)
	EventBus.worker_low_energy.connect(_on_worker_low_energy)
	EventBus.worker_low_condition.connect(_on_worker_low_condition)
	EventBus.hostile_spotted.connect(_on_hostile_spotted)
	EventBus.outlet_count_changed.connect(_on_outlet_count_changed)


func set_camera(cam: Camera2D) -> void:
	_camera = cam


func _process(delta: float) -> void:
	_tick_dedup(delta)
	_gc_cards()


func _tick_dedup(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var to_remove: Array = []
	for key in _dedup.keys():
		if now - float(_dedup[key]) > DEDUP_WINDOW_SEC:
			to_remove.append(key)
	for key in to_remove:
		_dedup.erase(key)


func _gc_cards() -> void:
	var to_remove: Array[Control] = []
	for card in _cards:
		if card == null or not is_instance_valid(card):
			to_remove.append(card)
	for card in to_remove:
		_cards.erase(card)


## Push a new alert. Returns the card node (useful for linking camera jump).
func push_alert(
	title: String,
	body: String = "",
	kind: int = Kind.INFO,
	target_node: Node = null,
) -> Control:
	# De-duplicate: same title+body within DEDUP_WINDOW_SEC is dropped.
	var dedup_key: int = hash(title + body)
	var now: float = Time.get_ticks_msec() / 1000.0
	if _dedup.has(dedup_key):
		return null
	_dedup[dedup_key] = now

	# Enforce max alert cap: remove oldest.
	while _cards.size() >= MAX_ALERTS:
		if _cards.size() == 0:
			break
		var oldest: Control = _cards[0]
		_cards.remove_at(0)
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()

	var card: Control = _build_card(title, body, kind, target_node)
	_container.add_child(card)
	_cards.append(card)
	return card


func _build_card(
	title: String,
	body: String,
	kind: int,
	target_node: Node,
) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_MIN_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.07, 0.92)
	style.border_color = KIND_COLORS[clampi(kind, 0, KIND_COLORS.size() - 1)]
	style.set_border_width_all(1)
	style.border_color.a = 0.85
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = CARD_PADDING
	style.content_margin_right = CARD_PADDING
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	# Accent bar.
	var accent_row := HBoxContainer.new()
	accent_row.add_theme_constant_override("separation", 6)
	vbox.add_child(accent_row)

	var dot := ColorRect.new()
	dot.color = KIND_COLORS[clampi(kind, 0, KIND_COLORS.size() - 1)]
	dot.custom_minimum_size = Vector2(4.0, 14.0)
	accent_row.add_child(dot)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_override("font", FONT)
	title_label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	title_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.97, 1.0))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	accent_row.add_child(title_label)

	# Body (hidden until expanded).
	var body_label: Label = null
	if not body.is_empty():
		body_label = Label.new()
		body_label.text = body
		body_label.add_theme_font_override("font", FONT)
		body_label.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
		body_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.80, 1.0))
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.visible = false
		vbox.add_child(body_label)

	# Hint text.
	var hint := Label.new()
	var hint_parts: Array[String] = []
	if not body.is_empty():
		hint_parts.append("LClick: expand")
	if target_node != null:
		hint_parts.append("LClick: focus")
	hint_parts.append("RClick: dismiss")
	hint.text = " | ".join(hint_parts)
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.42, 0.48, 0.55, 1.0))
	vbox.add_child(hint)

	# Interaction.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent) -> void:
		_on_card_input(event, card, body_label, target_node)
	)

	return card


func _on_card_input(
	event: InputEvent,
	card: Control,
	body_label: Label,
	target_node: Node,
) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == SettingsManager.primary_mouse_button():
		if target_node != null and is_instance_valid(target_node) and _camera != null:
			if _camera.has_method("follow_node"):
				_camera.call("follow_node", target_node)
			elif _camera.has_method("center_on") and target_node is Node2D:
				_camera.call("center_on", (target_node as Node2D).global_position)
		elif body_label != null and is_instance_valid(body_label):
			body_label.visible = not body_label.visible
	elif mb.button_index == SettingsManager.secondary_mouse_button():
		_dismiss_card(card)


func _dismiss_card(card: Control) -> void:
	if not is_instance_valid(card):
		return
	_cards.erase(card)
	card.queue_free()


# ── EventBus handlers ────────────────────────────────────────────────────────

func _on_worker_attacked(worker: Node) -> void:
	var wname: String = worker.call("display_name") if worker.has_method("display_name") else str(worker.name)
	push_alert(
		"%s is under attack!" % wname,
		"",
		Kind.COMBAT,
		worker if worker is Node2D else null,
	)


func _on_worker_low_energy(worker: Node, ratio: float) -> void:
	var wname: String = worker.call("display_name") if worker.has_method("display_name") else str(worker.name)
	var pct: int = int(roundf(ratio * 100.0))
	push_alert(
		"%s — energy at %d%%" % [wname, pct],
		"Needs Outlet",
		Kind.WARNING,
		worker if worker is Node2D else null,
	)


func _on_worker_low_condition(worker: Node, ratio: float) -> void:
	var wname: String = worker.call("display_name") if worker.has_method("display_name") else str(worker.name)
	var pct: int = int(roundf(ratio * 100.0))
	push_alert(
		"%s — condition at %d%%" % [wname, pct],
		"Needs Mech Dock",
		Kind.WARNING,
		worker if worker is Node2D else null,
	)


func _on_hostile_spotted(hostile: Node, spotter: Node) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if _hostile_spotted_times.has(hostile):
		if now - float(_hostile_spotted_times[hostile]) < 15.0:
			return
	_hostile_spotted_times[hostile] = now

	var spotter_name: String = spotter.call("display_name") if spotter.has_method("display_name") else str(spotter.name)
	push_alert(
		"Hostile spotted!",
		"Seen by %s" % spotter_name,
		Kind.DANGER,
		hostile if hostile is Node2D else null,
	)
	# Auto-pause the game on the first hostile sighting.
	if not GameState.is_paused():
		GameState.set_game_speed(0.0)


func _on_outlet_count_changed(count: int) -> void:
	if count == 0 and not _outlet_alert_sent:
		_outlet_alert_sent = true
		push_alert(
			"No outlet in colony!",
			"You need at least 1 outlet for your bots to recharge.",
			Kind.DANGER,
		)
	elif count > 0:
		_outlet_alert_sent = false
