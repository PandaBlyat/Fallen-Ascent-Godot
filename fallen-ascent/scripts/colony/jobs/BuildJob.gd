class_name BuildJob
extends Job
##
## Build a blueprint at `anchor`. Workers deliver each ingredient one unit at a
## time, then spend blueprint-specific build time and place a tile/object.
##

var anchor: Vector2i = Vector2i.ZERO
var blueprint_id: int = BuildBlueprint.Id.WALL
var rotation: int = 0
var footprint: Array[Vector2i] = []
var ingredients: Dictionary = {}
var delivered: Dictionary = {}
var material_kind: int = Item.Kind.SCRAP
var source_item: Node = null              ## Item being consumed; assigned at claim time
var progress: float = 0.0


func _init(t: Vector2i = Vector2i.ZERO, blueprint: int = BuildBlueprint.Id.WALL, rot: int = 0) -> void:
	kind = Kind.BUILD
	anchor = t
	blueprint_id = blueprint
	rotation = posmod(rot, 4)
	footprint = BuildBlueprint.footprint(blueprint_id, anchor, rotation)
	ingredients = BuildBlueprint.ingredients(blueprint_id)
	material_kind = next_missing_kind()


func target() -> Vector2i:
	return anchor


func has_all_materials() -> bool:
	for key in ingredients.keys():
		var k: int = int(key)
		if int(delivered.get(k, 0)) < int(ingredients[k]):
			return false
	return true


func next_missing_kind() -> int:
	for key in ingredients.keys():
		var k: int = int(key)
		if int(delivered.get(k, 0)) < int(ingredients[k]):
			return k
	return -1


func accept_delivered(kind_id: int, amount: int = 1) -> void:
	delivered[kind_id] = int(delivered.get(kind_id, 0)) + amount
	material_kind = next_missing_kind()


func build_duration() -> float:
	return BuildBlueprint.build_duration(blueprint_id)


func missing_items_text() -> String:
	var parts: Array[String] = []
	for key in ingredients.keys():
		var k: int = int(key)
		var missing: int = int(ingredients[k]) - int(delivered.get(k, 0))
		if missing > 0:
			parts.append("%s x%d" % [Item.kind_name(k), missing])
	if parts.is_empty():
		return "none"
	return ", ".join(parts)


func delivered_items_text() -> String:
	var parts: Array[String] = []
	for key in ingredients.keys():
		var k: int = int(key)
		var amount: int = int(delivered.get(k, 0))
		if amount > 0:
			parts.append("%s x%d" % [Item.kind_name(k), amount])
	if parts.is_empty():
		return "none"
	return ", ".join(parts)


func refund_items() -> Dictionary:
	var refund: Dictionary = {}
	for key in delivered.keys():
		var k: int = int(key)
		var amount: int = int(delivered.get(k, 0))
		var returned: int = int(floor(float(amount) * 0.5 + 0.5))
		if returned > 0:
			refund[k] = returned
	return refund


func refund_items_text() -> String:
	var refund: Dictionary = refund_items()
	if refund.is_empty():
		return "none"
	var parts: Array[String] = []
	for key in refund.keys():
		var k: int = int(key)
		parts.append("%s x%d" % [Item.kind_name(k), int(refund[k])])
	return ", ".join(parts)


