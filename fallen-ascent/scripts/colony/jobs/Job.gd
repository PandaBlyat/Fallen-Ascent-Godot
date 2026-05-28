class_name Job
extends RefCounted
##
## Base class for runtime jobs on the JobBoard. Not a Resource — jobs are
## not saved as files. Subclasses add their own payload (target tile, item
## ref, etc.) and the Worker switches on `kind`.
##

enum Kind { MINE, HAUL, BUILD, SCRAPE_RUST, CRAFT, OPERATE_STRUCTURE, SCRAPE_BIOMASS, DISMANTLE }

var kind: int = Kind.MINE
var claimed_by: Node = null   ## the Worker that owns this job, or null
## When > Time.get_ticks_msec(), the JobBoard skips this job in
## claim_next_for. Used when a worker fails to path to the target so the
## same job is not re-claimed every tick.
var blocked_until_msec: int = 0


func block_briefly(seconds: float = 1.25) -> void:
	blocked_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
