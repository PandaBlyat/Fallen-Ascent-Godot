class_name TechDatabase
extends RefCounted
##
## Hardcoded technology tree for the prototype. Mirrors BuildBlueprint's
## "code now, Resource later" pattern. When the tree stabilises this can
## migrate to .tres files; until then, keep all numbers tweakable here.
##
## Branch layout in grid space:
##   col 0 = Awakening (root)
##   col 1..3 = each branch's three rungs
##   col 4    = Sentience Forge capstone
##
## Branches by row:
##   row 0: Power
##   row 1: Refining
##   row 2: Sensors
##   row 3: Mind / Wisdom
##   row 4: Bodywork
##

const AWAKENING: StringName = &"awakening"
const POWER_I: StringName = &"power_i"
const POWER_II: StringName = &"power_ii"
const POWER_III: StringName = &"power_iii"
const REFINING_I: StringName = &"refining_i"
const REFINING_II: StringName = &"refining_ii"
const REFINING_III: StringName = &"refining_iii"
const SENSORS_I: StringName = &"sensors_i"
const FOCUSED_MIND: StringName = &"focused_mind"
const CALIBRATION: StringName = &"calibration"
const MECHANIC_DOCK: StringName = &"mechanic_dock"
const MECHANIC_ROOM: StringName = &"mechanic_room"
const SENTIENCE_FORGE: StringName = &"sentience_forge"


static func all() -> Array[TechData]:
	var out: Array[TechData] = []
	out.append(TechData.new(
		AWAKENING,
		"Awakening",
		"You came online. Basic walls, doors, lights, docks, repair benches, stockpiles, and a meditation pad are available from the start.",
		0,
		[],
		[
			BuildBlueprint.Id.WALL,
			BuildBlueprint.Id.DOOR,
			BuildBlueprint.Id.LIGHT,
			BuildBlueprint.Id.DOCK,
			BuildBlueprint.Id.REPAIR_BENCH,
			BuildBlueprint.Id.MEDITATION_PAD,
		],
		Vector2i(0, 2),
		"start",
	))

	# Power branch (row 0)
	out.append(TechData.new(
		POWER_I,
		"Power Grid I",
		"Lay charge pads to keep bots energised away from outlets.",
		40,
		[AWAKENING],
		[BuildBlueprint.Id.CHARGE_PAD],
		Vector2i(1, 0),
		"Power",
	))
	out.append(TechData.new(
		POWER_II,
		"Power Grid II",
		"Build a Fabricator to turn refined parts into datacores and charge cells.",
		90,
		[POWER_I],
		[BuildBlueprint.Id.FABRICATOR],
		Vector2i(2, 0),
		"Power",
	))
	out.append(TechData.new(
		POWER_III,
		"Power Grid III",
		"Battery banks (deferred). Reserved for a later pass.",
		180,
		[POWER_II],
		[],
		Vector2i(3, 0),
		"Power",
	))

	# Refining branch (row 1)
	out.append(TechData.new(
		REFINING_I,
		"Refining I",
		"Build an Extractor to pull plating and mechanisms out of conduits.",
		60,
		[AWAKENING],
		[BuildBlueprint.Id.EXTRACTOR],
		Vector2i(1, 1),
		"Refining",
	))
	out.append(TechData.new(
		REFINING_II,
		"Refining II",
		"Build an Assembly Press to recycle plating + datacores into useful parts.",
		120,
		[REFINING_I],
		[BuildBlueprint.Id.PARTS_LOOM],
		Vector2i(2, 1),
		"Refining",
	))
	out.append(TechData.new(
		REFINING_III,
		"Refining III",
		"Datacore-grade fabrication. Reserved for a later pass.",
		220,
		[REFINING_II],
		[],
		Vector2i(3, 1),
		"Refining",
	))

	# Sensors branch (row 2)
	out.append(TechData.new(
		SENSORS_I,
		"Sensors I",
		"Erect sensor masts to extend your vision over the megastructure.",
		50,
		[AWAKENING],
		[BuildBlueprint.Id.SENSOR],
		Vector2i(1, 2),
		"Sensors",
	))

	# Mind / Wisdom branch (row 3)
	out.append(TechData.new(
		FOCUSED_MIND,
		"Focused Mind",
		"Meditating bots produce wisdom 25% faster.",
		80,
		[AWAKENING],
		[],
		Vector2i(1, 3),
		"Mind",
	))
	out.append(TechData.new(
		CALIBRATION,
		"Calibration",
		"Unlocks the Calibration Shrine for future mental and social recovery.",
		160,
		[FOCUSED_MIND],
		[BuildBlueprint.Id.CALIBRATION_SHRINE],
		Vector2i(2, 3),
		"Mind",
	))

	# Bodywork branch (row 4)
	out.append(TechData.new(
		MECHANIC_DOCK,
		"Mechanic Dock",
		"Build a Mechanic Dock — the structural prerequisite for a Mechanic Room.",
		100,
		[AWAKENING],
		[BuildBlueprint.Id.MAINTENANCE_DOCK],
		Vector2i(1, 4),
		"Bodywork",
	))
	out.append(TechData.new(
		MECHANIC_ROOM,
		"Mechanic Room",
		"Designate enclosed Mechanic Rooms where an assigned bot can heal limbs of room occupants. (Healing effect itself lands in a follow-up pass.)",
		180,
		[MECHANIC_DOCK],
		[],
		Vector2i(2, 4),
		"Bodywork",
	))

	# Capstone
	out.append(TechData.new(
		SENTIENCE_FORGE,
		"Sentience Forge",
		"Unlocks the Sentience Cradle: build, fuel, wait, gain a new bot.",
		400,
		[REFINING_II, POWER_II, MECHANIC_DOCK],
		[BuildBlueprint.Id.SENTIENCE_CRADLE],
		Vector2i(4, 2),
		"Capstone",
	))
	return out


static func by_id(tech_id: StringName) -> TechData:
	for tech in all():
		if tech.id == tech_id:
			return tech
	return null
