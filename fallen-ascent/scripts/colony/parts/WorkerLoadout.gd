class_name WorkerLoadout
extends Resource
##
## A single starting worker's full build: display name, personality, equipped
## parts (parallel to `PartDatabase.SLOT_LAYOUT`) and skill levels. `derive()`
## folds parts + skills + personality into one flat stats dict that
## `Worker.apply_loadout` consumes. This is the one bridge between the embark
## screen and gameplay, so both sides read the same numbers.
##
## Skills are 0..SKILL_MAX. Personalities map 1:1 to `Worker.Personality` and to
## `WorkerLines` flavour buckets.
##

## Mirrors Worker.MOOD_BASELINE — kept local so the loadout can derive a mood
## baseline without a hard dependency on a live Worker node.
const MOOD_BASELINE: float = 80.0
const SKILL_MAX: int = 5

const SKILL_MINING: StringName = &"mining"
const SKILL_CONSTRUCTION: StringName = &"construction"
const SKILL_HAULING: StringName = &"hauling"
const SKILL_COMBAT: StringName = &"combat"
const SKILL_RESEARCH: StringName = &"research"

const SKILL_KEYS: Array[StringName] = [
	SKILL_MINING, SKILL_CONSTRUCTION, SKILL_HAULING, SKILL_COMBAT, SKILL_RESEARCH,
]
const SKILL_LABELS: Dictionary = {
	SKILL_MINING: "Mining",
	SKILL_CONSTRUCTION: "Construction",
	SKILL_HAULING: "Hauling",
	SKILL_COMBAT: "Combat",
	SKILL_RESEARCH: "Research",
}

## Specialty presets seed a skill spread AND grant a small role buff on top, so
## picking a role is a meaningful commitment, not just a skill preset. The embark
## screen cycles these so the player picks a "kind" of worker without
## micro-managing five sliders. `buff` is added onto the derived stats dict;
## `desc` is shown as the role tooltip in the embark screen.
const SPECIALTIES: Array[Dictionary] = [
	{"name": "Generalist", "skills": {SKILL_MINING: 1, SKILL_CONSTRUCTION: 1, SKILL_HAULING: 1, SKILL_COMBAT: 1, SKILL_RESEARCH: 1},
		"buff": {"work_speed": 0.08}, "desc": "Jack of all trades. +8% general work speed and a point in every skill."},
	{"name": "Miner",      "skills": {SKILL_MINING: 4, SKILL_HAULING: 2},
		"buff": {"mine_speed": 0.20}, "desc": "Rock-breaker. +20% mining speed on top of high Mining skill."},
	{"name": "Builder",    "skills": {SKILL_CONSTRUCTION: 4, SKILL_HAULING: 2},
		"buff": {"build_speed": 0.20}, "desc": "Fabricator. +20% build speed on top of high Construction skill."},
	{"name": "Hauler",     "skills": {SKILL_HAULING: 4, SKILL_MINING: 1},
		"buff": {"carry": 1, "move_speed": 6.0}, "desc": "Beast of burden. +1 carry and +6 move speed on top of high Hauling skill."},
	{"name": "Guard",      "skills": {SKILL_COMBAT: 4, SKILL_HAULING: 1},
		"buff": {"bash_min": 2.0, "bash_max": 3.0, "armor": 1.0}, "desc": "Sentinel. +2-3 bash and +1 armor on top of high Combat skill."},
	{"name": "Researcher", "skills": {SKILL_RESEARCH: 4, SKILL_CONSTRUCTION: 1},
		"buff": {"wisdom": 0.20}, "desc": "Analyst. +20% research yield on top of high Research skill."},
]

## Per-personality modifiers. `stats` are added onto the derived stats dict;
## `mood_baseline` is a flat shift and `mood_recovery_mult` scales how fast mood
## drifts back to baseline. Order matches Worker.Personality.
const PERSONALITY_MODS: Array[Dictionary] = [
	# 0 DUTIFUL — diligent, dependable worker.
	{"stats": {"work_speed": 0.10, "mine_speed": 0.05, "build_speed": 0.05}, "mood_baseline": 0.0, "mood_recovery_mult": 1.0},
	# 1 GRUMPY — hits harder, but perpetually unhappy.
	{"stats": {"bash_min": 2.0, "bash_max": 3.0}, "mood_baseline": -12.0, "mood_recovery_mult": 0.8},
	# 2 CHEERFUL — sunny and resilient of mood.
	{"stats": {"work_speed": 0.05}, "mood_baseline": 12.0, "mood_recovery_mult": 1.4},
	# 3 PHILOSOPHICAL — slow worker, brilliant researcher.
	{"stats": {"wisdom": 0.30, "work_speed": -0.08, "mine_speed": -0.05}, "mood_baseline": 0.0, "mood_recovery_mult": 1.0},
	# 4 PARANOID — watchful and evasive, slightly anxious.
	{"stats": {"sight": 2, "dodge": 0.04}, "mood_baseline": -6.0, "mood_recovery_mult": 1.0},
	# 5 STOIC — unflappable, holds the line.
	{"stats": {"armor": 1.0}, "mood_baseline": 4.0, "mood_recovery_mult": 1.25},
	# 6 NOSTALGIC — old, sturdy, a touch slow.
	{"stats": {"max_hp": 15.0, "energy_drain": -0.05, "work_speed": -0.04}, "mood_baseline": 0.0, "mood_recovery_mult": 1.0},
	# 7 COMPETITIVE — fast and driven, burns power doing it.
	{"stats": {"work_speed": 0.15, "mine_speed": 0.10, "build_speed": 0.10, "energy_drain": 0.18}, "mood_baseline": 0.0, "mood_recovery_mult": 1.0},
	# 8 GLITCHY — erratic but oddly dangerous and evasive.
	{"stats": {"bash_min": 1.0, "bash_max": 4.0, "dodge": 0.05, "energy_drain": 0.10}, "mood_baseline": -3.0, "mood_recovery_mult": 1.0},
]

@export var display_name: String = ""
@export var personality: int = 0
## Parallel to PartDatabase.SLOT_LAYOUT; each entry is a part id or &"" (empty).
@export var part_ids: PackedStringArray = PackedStringArray()
## StringName(skill) -> int level (0..SKILL_MAX).
@export var skills: Dictionary = {}
@export var specialty: String = "Generalist"


func _init() -> void:
	if part_ids.is_empty():
		part_ids = _empty_slots()


static func _empty_slots() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for _i in PartDatabase.SLOT_LAYOUT.size():
		out.append("")
	return out


## Total pool-point cost of the equipped parts.
func pool_cost() -> int:
	return PartDatabase.total_cost(part_ids)


func skill_level(skill: StringName) -> int:
	return int(skills.get(skill, 0))


## Apply a specialty preset by name (sets `specialty` + `skills`).
func set_specialty(spec_name: String) -> void:
	for spec in SPECIALTIES:
		if str(spec["name"]) == spec_name:
			specialty = spec_name
			skills = (spec["skills"] as Dictionary).duplicate()
			return


## Returns the specialty preset dict for `spec_name`, or an empty dict.
static func specialty_def(spec_name: String) -> Dictionary:
	for spec in SPECIALTIES:
		if str(spec["name"]) == spec_name:
			return spec
	return {}


## Human-readable description of the active role's buff, for tooltips.
static func role_desc(spec_name: String) -> String:
	var def: Dictionary = specialty_def(spec_name)
	return str(def.get("desc", "")) if not def.is_empty() else ""


## Fold parts + skills + personality into a flat stats dict for the worker.
func derive() -> Dictionary:
	var stats: Dictionary = PartDatabase.accumulate(part_ids)

	# Role buff: a small flat bonus to the role's signature stat(s).
	var role_def: Dictionary = specialty_def(specialty)
	if not role_def.is_empty():
		var buff: Dictionary = role_def.get("buff", {}) as Dictionary
		for key in buff:
			stats[key] = stats.get(key, 0.0) + buff[key]

	# Skills sharpen the relevant work, toughen combat, etc.
	stats["mine_speed"] += 0.08 * skill_level(SKILL_MINING)
	stats["build_speed"] += 0.08 * skill_level(SKILL_CONSTRUCTION)
	stats["carry"] += int(skill_level(SKILL_HAULING) / 2)
	stats["bash_min"] += 1.0 * skill_level(SKILL_COMBAT)
	stats["bash_max"] += 1.5 * skill_level(SKILL_COMBAT)
	stats["dodge"] += 0.01 * skill_level(SKILL_COMBAT)
	stats["wisdom"] += 0.10 * skill_level(SKILL_RESEARCH)

	# Personality fingerprint.
	var mood_baseline: float = MOOD_BASELINE
	var mood_recovery_mult: float = 1.0
	if personality >= 0 and personality < PERSONALITY_MODS.size():
		var pmod: Dictionary = PERSONALITY_MODS[personality]
		var pstats: Dictionary = pmod["stats"] as Dictionary
		for key in pstats:
			stats[key] = stats.get(key, 0.0) + pstats[key]
		mood_baseline += float(pmod.get("mood_baseline", 0.0))
		mood_recovery_mult = float(pmod.get("mood_recovery_mult", 1.0))

	# Comfort parts shift the mood baseline too (carried on the "mood" key).
	mood_baseline += float(stats.get("mood", 0.0))
	stats["mood_baseline"] = mood_baseline
	stats["mood_recovery_mult"] = mood_recovery_mult
	return stats


## Serialize to a plain dict (for save files / passing across scenes).
func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"personality": personality,
		"part_ids": Array(part_ids),
		"skills": skills.duplicate(),
		"specialty": specialty,
	}


static func from_dict(data: Dictionary) -> WorkerLoadout:
	var loadout := WorkerLoadout.new()
	loadout.display_name = str(data.get("display_name", ""))
	loadout.personality = int(data.get("personality", 0))
	var ids: PackedStringArray = PackedStringArray()
	for raw in data.get("part_ids", []) as Array:
		ids.append(str(raw))
	if ids.is_empty():
		ids = _empty_slots()
	loadout.part_ids = ids
	loadout.skills = (data.get("skills", {}) as Dictionary).duplicate()
	loadout.specialty = str(data.get("specialty", "Generalist"))
	return loadout
