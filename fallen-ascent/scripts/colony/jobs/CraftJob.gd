class_name CraftJob
extends Job
##
## Craft one placeable object at a crafting spot. Workers deliver each
## ingredient, work for the object's craft duration, then output object item.
##

var station_anchor: Vector2i = Vector2i.ZERO
var object_kind: int = Item.Kind.STORAGE_BIN
var ingredients: Dictionary = {}
var delivered: Dictionary = {}
var material_kind: int = Item.Kind.SCRAP
var source_item: Node = null
var progress: float = 0.0


func _init(anchor: Vector2i = Vector2i.ZERO, crafted_kind: int = Item.Kind.STORAGE_BIN) -> void:
	kind = Kind.CRAFT
	station_anchor = anchor
	object_kind = crafted_kind
	ingredients = Item.craft_recipe(object_kind)
	material_kind = next_missing_kind()


func target() -> Vector2i:
	return station_anchor


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


func craft_duration() -> float:
	return Item.craft_duration(object_kind)


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
