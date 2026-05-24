class_name Job
extends RefCounted
##
## Base class for runtime jobs on the JobBoard. Not a Resource — jobs are
## not saved as files. Subclasses add their own payload (target tile, item
## ref, etc.) and the Worker switches on `kind`.
##

enum Kind { MINE, HAUL, BUILD, SCRAPE_RUST }

var kind: int = Kind.MINE
var claimed_by: Node = null   ## the Worker that owns this job, or null
