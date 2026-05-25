class_name OperateStructureJob
extends Job
##
## Worker-run production cycle for powered structures. Workers deliver inputs,
## operate the machine, then StructureManager creates the output.
##

var anchor: Vector2i = Vector2i.ZERO
var structure_id: int = BuildBlueprint.Id.EXTRACTOR
var ingredients: Dictionary = {}
var delivered: Dictionary = {}
var material_kind: int = Item.Kind.SCRAP
var source_item: Node = null
var progress: float = 0.0


func _init(target_anchor: Vector2i = Vector2i.ZERO, id: int = BuildBlueprint.Id.EXTRACTOR) -> void:
	kind = Kind.OPERATE_STRUCTURE
	anchor = target_anchor
	structure_id = id
	ingredients = BuildBlueprint.production_inputs(structure_id)
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


func operate_duration() -> float:
	return BuildBlueprint.production_interval(structure_id)


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
