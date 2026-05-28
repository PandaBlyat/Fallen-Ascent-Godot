class_name PartDatabase
##
## Cogmind-style body-part registry for worker bots. A bare worker is a "shell":
## slow, low bash damage, tiny carry. Parts slot into the shell to build a wide
## range of bots. Parts are grouped by SLOT and gated behind a TIER (1..5) that
## the player unlocks permanently with achievement points; within a run they are
## equipped from a per-embark point pool (`cost`).
##
## Pure data + static helpers — no Node, no state. Add new parts by appending to
## `PARTS`; the embark screen, worker derivation, and tier gating pick them up
## automatically. Keep `PARTS` append-only so saved loadouts keep resolving.
##
## Stat keys produced by `accumulate` (all additive onto SHELL unless noted):
##   move_speed     px/sec walk speed
##   work_speed     general task-rate multiplier (craft/operate)
##   mine_speed     mining-rate multiplier
##   build_speed    build-rate multiplier
##   carry          max carried stack size (int)
##   max_hp         combat hit points
##   armor          flat damage absorbed per hit
##   bash_min/max   melee damage range
##   sight          bonus tiles of vision
##   energy_recharge   charge-rate multiplier
##   energy_drain      drain-rate multiplier (lower = thriftier)
##   wisdom         research-gain multiplier
##   dodge          0..1 chance to avoid a swing
##   mood           flat shift to mood baseline
##

enum Slot { POWER, PROPULSION, MANIPULATION, UTILITY, WEAPON }

const SLOT_LABELS: Dictionary = {
	Slot.POWER: "Power",
	Slot.PROPULSION: "Propulsion",
	Slot.MANIPULATION: "Manipulation",
	Slot.UTILITY: "Utility",
	Slot.WEAPON: "Weapon",
}

## The fixed slot layout every worker chassis exposes. Index positions are how
## `WorkerLoadout.part_ids` maps to slots, so this is append-only too.
const SLOT_LAYOUT: Array[int] = [
	Slot.POWER,
	Slot.PROPULSION, Slot.PROPULSION,
	Slot.MANIPULATION, Slot.MANIPULATION,
	Slot.UTILITY, Slot.UTILITY,
	Slot.WEAPON,
]

const MAX_TIER: int = 5

## Bare-shell baseline. A worker with no parts uses exactly these numbers — a
## sluggish walking chassis that can barely fight or haul. Parts add onto this.
const SHELL: Dictionary = {
	"move_speed": 30.0,
	"work_speed": 0.5,
	"mine_speed": 0.5,
	"build_speed": 0.5,
	"carry": 1,
	"max_hp": 55.0,
	"armor": 0.0,
	"bash_min": 1.0,
	"bash_max": 3.0,
	"sight": 0,
	"energy_recharge": 1.0,
	"energy_drain": 1.0,
	"wisdom": 1.0,
	"dodge": 0.05,
	"mood": 0.0,
}

## Master part list. `atlas_index` reserves a placeholder icon cell for later art.
const PARTS: Array[Dictionary] = [
	# ---- POWER (energy economy, some structural mass) -------------------------
	{"id": &"pwr_salvaged_cell", "name": "Salvaged Cell", "slot": Slot.POWER, "tier": 1, "cost": 2, "atlas_index": 0,
		"desc": "A scavenged battery. Modest recharge.",
		"mods": {"energy_recharge": 0.30}},
	{"id": &"pwr_ion_battery", "name": "Ion Battery", "slot": Slot.POWER, "tier": 2, "cost": 4, "atlas_index": 1,
		"desc": "Stable ion stack. Charges noticeably faster.",
		"mods": {"energy_recharge": 0.70, "max_hp": 5.0}},
	{"id": &"pwr_fusion_cell", "name": "Fusion Cell", "slot": Slot.POWER, "tier": 3, "cost": 7, "atlas_index": 2,
		"desc": "Contained fusion. Fast charge, sturdier frame.",
		"mods": {"energy_recharge": 1.20, "max_hp": 12.0, "energy_drain": -0.10}},
	{"id": &"pwr_antimatter_core", "name": "Antimatter Core", "slot": Slot.POWER, "tier": 4, "cost": 10, "atlas_index": 3,
		"desc": "Dense and efficient. Sips power while working.",
		"mods": {"energy_recharge": 1.80, "energy_drain": -0.22}},
	{"id": &"pwr_singularity_reactor", "name": "Singularity Reactor", "slot": Slot.POWER, "tier": 5, "cost": 14, "atlas_index": 4,
		"desc": "A caged microsingularity. Near-limitless uptime.",
		"mods": {"energy_recharge": 2.60, "energy_drain": -0.38, "max_hp": 20.0}},

	# ---- PROPULSION (movement, some evasion) ----------------------------------
	{"id": &"prop_strut_legs", "name": "Strut Legs", "slot": Slot.PROPULSION, "tier": 1, "cost": 2, "atlas_index": 5,
		"desc": "Simple welded struts. Gets you walking.",
		"mods": {"move_speed": 14.0}},
	{"id": &"prop_servo_legs", "name": "Servo Legs", "slot": Slot.PROPULSION, "tier": 2, "cost": 4, "atlas_index": 6,
		"desc": "Powered servos. Brisk and reliable.",
		"mods": {"move_speed": 24.0}},
	{"id": &"prop_piston_legs", "name": "Piston Legs", "slot": Slot.PROPULSION, "tier": 3, "cost": 7, "atlas_index": 7,
		"desc": "Hydraulic stride. Covers ground quickly.",
		"mods": {"move_speed": 34.0}},
	{"id": &"prop_hover_pads", "name": "Hover Pads", "slot": Slot.PROPULSION, "tier": 4, "cost": 10, "atlas_index": 8,
		"desc": "Frictionless float. Slips past blows.",
		"mods": {"move_speed": 30.0, "dodge": 0.05}},
	{"id": &"prop_grav_treads", "name": "Grav Treads", "slot": Slot.PROPULSION, "tier": 5, "cost": 14, "atlas_index": 9,
		"desc": "Gravitic treads. Fastest chassis going.",
		"mods": {"move_speed": 52.0, "dodge": 0.05}},

	# ---- MANIPULATION (work speed, carry) -------------------------------------
	{"id": &"man_clamp_arm", "name": "Clamp Arm", "slot": Slot.MANIPULATION, "tier": 1, "cost": 2, "atlas_index": 10,
		"desc": "Basic gripper. A bit of everything.",
		"mods": {"work_speed": 0.18, "mine_speed": 0.18, "build_speed": 0.18, "carry": 1}},
	{"id": &"man_hydraulic_arm", "name": "Hydraulic Arm", "slot": Slot.MANIPULATION, "tier": 2, "cost": 4, "atlas_index": 11,
		"desc": "Strong all-rounder. Carries more.",
		"mods": {"work_speed": 0.30, "mine_speed": 0.30, "build_speed": 0.30, "carry": 1}},
	{"id": &"man_drill_arm", "name": "Drill Arm", "slot": Slot.MANIPULATION, "tier": 3, "cost": 7, "atlas_index": 12,
		"desc": "Mining specialist. Tears through rock.",
		"mods": {"mine_speed": 0.60, "work_speed": 0.22, "build_speed": 0.12, "carry": 1}},
	{"id": &"man_fabricator_arm", "name": "Fabricator Arm", "slot": Slot.MANIPULATION, "tier": 4, "cost": 10, "atlas_index": 13,
		"desc": "Construction specialist. Builds and crafts fast.",
		"mods": {"build_speed": 0.65, "work_speed": 0.40, "mine_speed": 0.15, "carry": 1}},
	{"id": &"man_omni_manipulator", "name": "Omni-Manipulator", "slot": Slot.MANIPULATION, "tier": 5, "cost": 14, "atlas_index": 14,
		"desc": "Does everything, brilliantly. Hauls heavy.",
		"mods": {"work_speed": 0.60, "mine_speed": 0.60, "build_speed": 0.60, "carry": 2}},

	# ---- UTILITY (durability, vision, mind, comfort) --------------------------
	{"id": &"util_plate_armor", "name": "Plate Armor", "slot": Slot.UTILITY, "tier": 1, "cost": 2, "atlas_index": 15,
		"desc": "Bolt-on plating. Soaks light hits.",
		"mods": {"max_hp": 20.0, "armor": 1.0}},
	{"id": &"util_optical_sensor", "name": "Optical Sensor", "slot": Slot.UTILITY, "tier": 1, "cost": 2, "atlas_index": 16,
		"desc": "Extends visual range.",
		"mods": {"sight": 2}},
	{"id": &"util_composite_plating", "name": "Composite Plating", "slot": Slot.UTILITY, "tier": 2, "cost": 4, "atlas_index": 17,
		"desc": "Layered composite. Tougher shell.",
		"mods": {"max_hp": 35.0, "armor": 2.0}},
	{"id": &"util_logic_coprocessor", "name": "Logic Coprocessor", "slot": Slot.UTILITY, "tier": 2, "cost": 4, "atlas_index": 18,
		"desc": "Crunches research data faster.",
		"mods": {"wisdom": 0.40}},
	{"id": &"util_reactive_armor", "name": "Reactive Armor", "slot": Slot.UTILITY, "tier": 3, "cost": 7, "atlas_index": 19,
		"desc": "Reactive plates. Hardy and nimble.",
		"mods": {"max_hp": 45.0, "armor": 3.0, "dodge": 0.04}},
	{"id": &"util_comfort_module", "name": "Comfort Module", "slot": Slot.UTILITY, "tier": 3, "cost": 7, "atlas_index": 20,
		"desc": "Dampens stress. Keeps spirits up.",
		"mods": {"mood": 12.0}},
	{"id": &"util_nano_weave", "name": "Nano-Weave", "slot": Slot.UTILITY, "tier": 4, "cost": 10, "atlas_index": 21,
		"desc": "Self-knitting weave. Very durable.",
		"mods": {"max_hp": 60.0, "armor": 4.0}},
	{"id": &"util_aegis_field", "name": "Aegis Field", "slot": Slot.UTILITY, "tier": 5, "cost": 14, "atlas_index": 22,
		"desc": "Projected barrier. Near-impervious.",
		"mods": {"max_hp": 90.0, "armor": 6.0, "dodge": 0.06}},

	# ---- WEAPON (bash damage) -------------------------------------------------
	{"id": &"wpn_bash_plate", "name": "Bash Plate", "slot": Slot.WEAPON, "tier": 1, "cost": 2, "atlas_index": 23,
		"desc": "A reinforced ram. Better than fists.",
		"mods": {"bash_min": 3.0, "bash_max": 5.0}},
	{"id": &"wpn_impact_hammer", "name": "Impact Hammer", "slot": Slot.WEAPON, "tier": 2, "cost": 4, "atlas_index": 24,
		"desc": "Kinetic hammer. Solid hits.",
		"mods": {"bash_min": 7.0, "bash_max": 11.0}},
	{"id": &"wpn_plasma_cutter", "name": "Plasma Cutter", "slot": Slot.WEAPON, "tier": 3, "cost": 7, "atlas_index": 25,
		"desc": "Superheated edge. Cuts deep.",
		"mods": {"bash_min": 12.0, "bash_max": 18.0}},
	{"id": &"wpn_rail_striker", "name": "Rail Striker", "slot": Slot.WEAPON, "tier": 4, "cost": 10, "atlas_index": 26,
		"desc": "Rail-driven strike. Brutal.",
		"mods": {"bash_min": 18.0, "bash_max": 26.0}},
	{"id": &"wpn_annihilator", "name": "Annihilator", "slot": Slot.WEAPON, "tier": 5, "cost": 14, "atlas_index": 27,
		"desc": "Devastating melee array. Few survive it.",
		"mods": {"bash_min": 28.0, "bash_max": 40.0}},
]

## Build a fast id -> part lookup once. Static init runs on first access.
static var _by_id: Dictionary = _index_parts()


static func _index_parts() -> Dictionary:
	var out: Dictionary = {}
	for part in PARTS:
		out[part["id"] as StringName] = part
	return out


## Returns the part dict for `id`, or an empty dict if unknown (e.g. a saved id
## that no longer exists). Never returns null so callers can read freely.
static func part(id: StringName) -> Dictionary:
	if id == &"" or not _by_id.has(id):
		return {}
	return _by_id[id] as Dictionary


static func has_part(id: StringName) -> bool:
	return id != &"" and _by_id.has(id)


static func slot_label(slot: int) -> String:
	return str(SLOT_LABELS.get(slot, "Slot"))


## Parts for one slot at or below `max_tier`, sorted by tier then cost. Used by
## the embark part-picker so only unlocked tiers show up.
static func parts_for(slot: int, max_tier: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part_dict in PARTS:
		if int(part_dict["slot"]) == slot and int(part_dict["tier"]) <= max_tier:
			out.append(part_dict)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) < int(b["tier"])
		return int(a["cost"]) < int(b["cost"]))
	return out


## Total pool-point cost of an equipped part-id list.
static func total_cost(part_ids: PackedStringArray) -> int:
	var sum: int = 0
	for raw in part_ids:
		var p: Dictionary = part(StringName(raw))
		if not p.is_empty():
			sum += int(p["cost"])
	return sum


## Fold the shell baseline plus every equipped part's mods into one stats dict.
## Unknown / empty ids are skipped. The result is a fresh dict the caller owns.
static func accumulate(part_ids: PackedStringArray) -> Dictionary:
	var stats: Dictionary = SHELL.duplicate(true)
	for raw in part_ids:
		var p: Dictionary = part(StringName(raw))
		if p.is_empty():
			continue
		var mods: Dictionary = p["mods"] as Dictionary
		for key in mods:
			stats[key] = stats.get(key, 0.0) + mods[key]
	return stats
