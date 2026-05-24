class_name FloatingText
extends Node2D
##
## World-space floating text. Listens to combat hits and dodges, spawns a short
## upward-rising label. Lightweight: one Node2D per active label, freed on
## fade-out. No per-frame allocations after spawn.
##

const LIFETIME_SECONDS: float = 0.85
const RISE_DISTANCE_PX: float = 14.0
const HORIZONTAL_JITTER_PX: float = 4.0
const FONT_SIZE: int = 11

var _entries: Array[Dictionary] = []
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	EventBus.combat_hit.connect(_on_combat_hit)
	EventBus.combat_dodged.connect(_on_combat_dodged)
	z_index = 1000


func _on_combat_hit(_attacker: Node, target: Node, damage: float) -> void:
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return
	_spawn((target as Node2D).global_position, "%d" % int(roundf(damage)), Color(1.0, 0.4, 0.35))


func _on_combat_dodged(_attacker: Node, target: Node) -> void:
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return
	_spawn((target as Node2D).global_position, "dodge", Color(0.55, 0.85, 1.0))


func _spawn(world_pos: Vector2, text: String, color: Color) -> void:
	_entries.append({
		"text": text,
		"color": color,
		"origin": world_pos + Vector2(randf_range(-HORIZONTAL_JITTER_PX, HORIZONTAL_JITTER_PX), -8.0),
		"age": 0.0,
	})
	if _entries.size() > 64:
		_entries.pop_front()
	queue_redraw()


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	var i: int = _entries.size() - 1
	while i >= 0:
		_entries[i]["age"] = float(_entries[i]["age"]) + delta
		if float(_entries[i]["age"]) >= LIFETIME_SECONDS:
			_entries.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	for entry in _entries:
		var age: float = float(entry["age"])
		var t: float = clampf(age / LIFETIME_SECONDS, 0.0, 1.0)
		var origin: Vector2 = entry["origin"] as Vector2
		var pos := origin + Vector2(0.0, -RISE_DISTANCE_PX * t)
		var color: Color = entry["color"] as Color
		color.a = 1.0 - t
		var text: String = entry["text"] as String
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		draw_string(_font, pos + Vector2(-size.x * 0.5, 0.0) + Vector2(1, 1), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, color.a * 0.7))
		draw_string(_font, pos + Vector2(-size.x * 0.5, 0.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
