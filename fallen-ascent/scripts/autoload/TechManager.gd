extends Node
##
## Runs the research economy. Stores accumulated wisdom and the set of
## unlocked tech ids. Bots deposit wisdom while meditating; the HUD reads
## `wisdom` for the resource strip and calls `try_unlock` from the tech
## panel.
##
## Save layer: state is intentionally NOT persisted yet — when the save
## system lands, snapshot `wisdom` and `unlocked` (see to-do-list.md).
##

var wisdom: float = 0.0
var unlocked: Dictionary = {}                       ## StringName -> true


func _ready() -> void:
	# Seed the free root unlock so the starter blueprints are buildable.
	unlocked[TechDatabase.AWAKENING] = true


func reset() -> void:
	wisdom = 0.0
	unlocked.clear()
	unlocked[TechDatabase.AWAKENING] = true
	EventBus.wisdom_changed.emit(wisdom)


func add_wisdom(amount: float) -> void:
	if amount <= 0.0:
		return
	wisdom += amount
	EventBus.wisdom_changed.emit(wisdom)


func is_unlocked(tech_id: StringName) -> bool:
	return unlocked.has(tech_id)


func can_unlock(tech_id: StringName) -> bool:
	if is_unlocked(tech_id):
		return false
	var tech: TechData = TechDatabase.by_id(tech_id)
	if tech == null:
		return false
	for prereq in tech.prerequisites:
		if not is_unlocked(prereq):
			return false
	return wisdom >= float(tech.wisdom_cost)


func prerequisites_met(tech_id: StringName) -> bool:
	var tech: TechData = TechDatabase.by_id(tech_id)
	if tech == null:
		return false
	for prereq in tech.prerequisites:
		if not is_unlocked(prereq):
			return false
	return true


func try_unlock(tech_id: StringName) -> bool:
	if is_unlocked(tech_id):
		return false
	var tech: TechData = TechDatabase.by_id(tech_id)
	if tech == null:
		return false
	if not prerequisites_met(tech_id):
		return false
	if wisdom < float(tech.wisdom_cost):
		return false
	wisdom -= float(tech.wisdom_cost)
	unlocked[tech_id] = true
	EventBus.wisdom_changed.emit(wisdom)
	EventBus.tech_unlocked.emit(tech_id)
	return true


func is_build_unlocked(build_id: int) -> bool:
	for tech in TechDatabase.all():
		if not is_unlocked(tech.id):
			continue
		if tech.unlocked_build_ids.has(build_id):
			return true
	return false


func tech_unlocking(build_id: int) -> TechData:
	for tech in TechDatabase.all():
		if tech.unlocked_build_ids.has(build_id):
			return tech
	return null
