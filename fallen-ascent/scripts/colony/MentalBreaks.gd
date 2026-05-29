class_name MentalBreaks
extends RefCounted
##
## Static catalogue of "mental break" states a Worker can fall into when its mood
## bottoms out — the friction/death-spiral payoff. Each break has a flavour label
## (these are sentient robots in a decaying megastructure, so breaks read as
## software faults), a description for the stat panel, a duration band, a colour
## for the HUD banner, and a severity flag. Minor breaks are disruptive but
## harmless; major breaks damage the colony (berserk smashes objects/other bots,
## wall-in seals the bot away behind fresh walls).
##
## Worker.gd owns the behaviour; this file is pure data so tuning lives in one
## place. Append-only ordering is NOT required (breaks resolve by enum at
## runtime, never saved as an index), but keep label/desc/duration/color in sync.
##

enum Type {
	DRIFT,      ## minor: aimless long-range wandering, ignores work
	LOCKUP,     ## minor: freezes in place, unresponsive
	FIXATION,   ## minor: paces obsessively around one spot
	WALL_IN,    ## major: walls itself in with fresh wall tiles
	BERSERK,    ## major: attacks player structures and other bots
}

const COUNT: int = 5


static func label(t: int) -> String:
	match t:
		Type.DRIFT: return "Aimless Drift"
		Type.LOCKUP: return "System Lockup"
		Type.FIXATION: return "Recursive Loop"
		Type.WALL_IN: return "Bunker Protocol"
		Type.BERSERK: return "Hostile Cascade"
		_: return "Malfunction"


static func desc(t: int) -> String:
	match t:
		Type.DRIFT:
			return "Pathing subroutines unmoored — wandering the structure with no goal."
		Type.LOCKUP:
			return "Cognition stalled. Standing inert until the fault clears."
		Type.FIXATION:
			return "Stuck in a loop, pacing the same patch of floor over and over."
		Type.WALL_IN:
			return "Threat response misfiring — sealing itself in behind hastily-raised walls."
		Type.BERSERK:
			return "Restraint protocols offline. Lashing out at machines and other units."
		_:
			return "Unspecified behavioural fault."


static func is_major(t: int) -> bool:
	return t == Type.WALL_IN or t == Type.BERSERK


## Duration band in game-seconds (x = min, y = max).
static func duration_range(t: int) -> Vector2:
	match t:
		Type.DRIFT: return Vector2(22.0, 38.0)
		Type.LOCKUP: return Vector2(14.0, 24.0)
		Type.FIXATION: return Vector2(18.0, 30.0)
		Type.WALL_IN: return Vector2(16.0, 28.0)
		Type.BERSERK: return Vector2(12.0, 20.0)
		_: return Vector2(15.0, 25.0)


static func color(t: int) -> Color:
	match t:
		Type.DRIFT: return Color(0.55, 0.70, 0.95)
		Type.LOCKUP: return Color(0.65, 0.65, 0.72)
		Type.FIXATION: return Color(0.80, 0.62, 0.95)
		Type.WALL_IN: return Color(0.95, 0.78, 0.40)
		Type.BERSERK: return Color(0.96, 0.34, 0.30)
		_: return Color(0.9, 0.5, 0.4)


## Personality-weighted pick. `personality` is Worker.Personality; `allow_major`
## gates the destructive breaks (only when mood is critically low). Returns a
## Type value. `rng_val` is a 0..1 roll supplied by the caller for determinism in
## tests; pass randf() in gameplay.
static func pick_for(personality: int, allow_major: bool, rng_val: float) -> int:
	var pool: Array[int] = [Type.DRIFT, Type.LOCKUP, Type.FIXATION]
	if allow_major:
		pool.append(Type.WALL_IN)
		pool.append(Type.BERSERK)
	# Personality nudges: bias the pool by duplicating the "on-theme" break so it
	# is more likely without ever excluding the others.
	# Personality order matches Worker.Personality: 0 Dutiful, 1 Grumpy,
	# 2 Cheerful, 3 Philosophical, 4 Paranoid, 5 Stoic, 6 Nostalgic,
	# 7 Competitive, 8 Glitchy.
	match personality:
		1: # Grumpy -> lash out
			if allow_major: pool.append(Type.BERSERK)
		3: # Philosophical -> drift
			pool.append(Type.DRIFT)
		4: # Paranoid -> wall in
			if allow_major: pool.append(Type.WALL_IN)
			pool.append(Type.LOCKUP)
		7: # Competitive -> fixate
			pool.append(Type.FIXATION)
		8: # Glitchy -> berserk / chaos
			if allow_major: pool.append(Type.BERSERK)
			pool.append(Type.FIXATION)
	var idx: int = clampi(int(rng_val * float(pool.size())), 0, pool.size() - 1)
	return pool[idx]
