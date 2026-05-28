class_name JobBoard
extends Node
##
## Holds the queue of unclaimed and in-flight jobs for one colony site.
## Workers pull from `claim_next_for`; designators add via `add_mine_job`,
## `add_haul_job`, and `add_build_job`. Local signals only — no EventBus
## traffic.
##

signal job_added(job: Job)
signal job_completed(job: Job)
signal job_cancelled(job: Job)

var pending: Array[Job] = []
var _mine_targets: Dictionary = {}   ## Vector2i -> MineJob, for fast cancel/dedup
var _build_targets: Dictionary = {}  ## Vector2i footprint cell -> BuildJob
var _scrape_targets: Dictionary = {} ## Vector2i -> Job
var _scrape_biomass_targets: Dictionary = {} ## Vector2i -> Job
var _operation_targets: Dictionary = {} ## Vector2i -> OperateStructureJob
## Chunk-coord -> Array[Job]. Lets claim_next_for scan only nearby
## chunks first instead of the full pending list each poll.
var _pending_by_chunk: Dictionary = {}
## Prevents stale job references when item coordinates change dynamically.
var _job_indexed_chunk: Dictionary = {}

const SCRAPE_RUST_JOB_SCRIPT: Script = preload("res://scripts/colony/jobs/ScrapeRustJob.gd")
const SCRAPE_BIOMASS_JOB_SCRIPT: Script = preload("res://scripts/colony/jobs/ScrapeBiomassJob.gd")
const CRAFT_JOB_SCRIPT: Script = preload("res://scripts/colony/jobs/CraftJob.gd")
const OPERATE_STRUCTURE_JOB_SCRIPT: Script = preload("res://scripts/colony/jobs/OperateStructureJob.gd")
## Chunk-radius scanned by claim_next_for before it falls back to the
## global pending list. 1 means worker chunk + 8 neighbors (3x3).
const NEAR_CHUNK_RADIUS: int = 1


func add_mine_job(target: Vector2i) -> MineJob:
	if _mine_targets.has(target):
		return _mine_targets[target] as MineJob
	var job := MineJob.new(target)
	pending.append(job)
	_mine_targets[target] = job
	_index_job(job)
	job_added.emit(job)
	return job


func cancel_mine_at(target: Vector2i) -> void:
	if not _mine_targets.has(target):
		return
	var job: MineJob = _mine_targets[target]
	_mine_targets.erase(target)
	pending.erase(job)
	_unindex_job(job)
	# If a worker has it claimed, let them notice and bail on next tick.
	job_cancelled.emit(job)


func has_mine_at(target: Vector2i) -> bool:
	return _mine_targets.has(target)


func add_scrape_rust_job(target: Vector2i) -> Job:
	if _scrape_targets.has(target):
		return _scrape_targets[target] as Job
	var job: Job = SCRAPE_RUST_JOB_SCRIPT.new(target) as Job
	pending.append(job)
	_scrape_targets[target] = job
	_index_job(job)
	job_added.emit(job)
	return job


func cancel_scrape_rust_at(target: Vector2i) -> void:
	if not _scrape_targets.has(target):
		return
	var job: Job = _scrape_targets[target] as Job
	_scrape_targets.erase(target)
	pending.erase(job)
	_unindex_job(job)
	job_cancelled.emit(job)


func has_scrape_rust_at(target: Vector2i) -> bool:
	return _scrape_targets.has(target)


func scrape_rust_count() -> int:
	return _scrape_targets.size()


func add_scrape_biomass_job(target: Vector2i) -> Job:
	if _scrape_biomass_targets.has(target):
		return _scrape_biomass_targets[target] as Job
	var job: Job = SCRAPE_BIOMASS_JOB_SCRIPT.new(target) as Job
	pending.append(job)
	_scrape_biomass_targets[target] = job
	_index_job(job)
	job_added.emit(job)
	return job


func cancel_scrape_biomass_at(target: Vector2i) -> void:
	if not _scrape_biomass_targets.has(target):
		return
	var job: Job = _scrape_biomass_targets[target] as Job
	_scrape_biomass_targets.erase(target)
	pending.erase(job)
	_unindex_job(job)
	job_cancelled.emit(job)


func has_scrape_biomass_at(target: Vector2i) -> bool:
	return _scrape_biomass_targets.has(target)


func scrape_biomass_count() -> int:
	return _scrape_biomass_targets.size()


func cancel_order_at(grid: Vector2i) -> bool:
	if _mine_targets.has(grid):
		cancel_mine_at(grid)
		return true
	if _scrape_targets.has(grid):
		cancel_scrape_rust_at(grid)
		return true
	if _scrape_biomass_targets.has(grid):
		cancel_scrape_biomass_at(grid)
		return true
	if _build_targets.has(grid):
		cancel_build_at(grid)
		return true
	return false


func add_haul_job(item: Node, zone: Node, cell: Vector2i) -> HaulJob:
	var job := HaulJob.new(item, zone, cell)
	pending.append(job)
	_index_job(job)
	job_added.emit(job)
	return job


## Cancel all haul jobs targeting `zone` (any cell). Returns the cells
## whose reservations should be released by the caller (StockpileManager).
func cancel_hauls_to_zone(zone: Node) -> Array[Vector2i]:
	var cancelled: Array[Vector2i] = []
	var i: int = pending.size() - 1
	while i >= 0:
		var j: Job = pending[i]
		if j is HaulJob and (j as HaulJob).dropoff_zone == zone:
			cancelled.append((j as HaulJob).dropoff)
			pending.remove_at(i)
			_unindex_job(j)
			job_cancelled.emit(j)
		i -= 1
	return cancelled


## Cancel a single haul job that targets `zone` at `cell`. Returns true if
## a job was found and cancelled.
func cancel_haul_to(zone: Node, cell: Vector2i) -> bool:
	for i in range(pending.size()):
		var j: Job = pending[i]
		if j is HaulJob and (j as HaulJob).dropoff_zone == zone \
				and (j as HaulJob).dropoff == cell:
			pending.remove_at(i)
			_unindex_job(j)
			job_cancelled.emit(j)
			return true
	return false


func add_build_job(target: Vector2i, blueprint_id: int = BuildBlueprint.Id.WALL, rotation: int = 0) -> BuildJob:
	for cell in BuildBlueprint.footprint(blueprint_id, target, rotation):
		if _build_targets.has(cell):
			return _build_targets[cell] as BuildJob
	var job := BuildJob.new(target, blueprint_id, rotation)
	pending.append(job)
	for cell in job.footprint:
		_build_targets[cell] = job
	_index_job(job)
	job_added.emit(job)
	return job


func add_craft_job(station_anchor: Vector2i, object_kind: int) -> CraftJob:
	var job: CraftJob = CRAFT_JOB_SCRIPT.new(station_anchor, object_kind) as CraftJob
	pending.append(job)
	_index_job(job)
	job_added.emit(job)
	return job


func add_operation_job(anchor: Vector2i, structure_id: int) -> OperateStructureJob:
	if _operation_targets.has(anchor):
		return _operation_targets[anchor] as OperateStructureJob
	var job: OperateStructureJob = OPERATE_STRUCTURE_JOB_SCRIPT.new(anchor, structure_id) as OperateStructureJob
	pending.append(job)
	_operation_targets[anchor] = job
	_index_job(job)
	job_added.emit(job)
	return job


func operation_job_at(anchor: Vector2i) -> OperateStructureJob:
	return _operation_targets.get(anchor) as OperateStructureJob


func operation_count_at(anchor: Vector2i) -> int:
	return 1 if _operation_targets.has(anchor) else 0


func cancel_craft_jobs_at(station_anchor: Vector2i) -> int:
	var cancelled: int = 0
	var i: int = pending.size() - 1
	while i >= 0:
		var job: Job = pending[i]
		if job is CraftJob and (job as CraftJob).station_anchor == station_anchor:
			pending.remove_at(i)
			_unindex_job(job)
			job_cancelled.emit(job)
			cancelled += 1
		i -= 1
	return cancelled


func craft_count_at(station_anchor: Vector2i) -> int:
	var count: int = 0
	for job in pending:
		if job is CraftJob and (job as CraftJob).station_anchor == station_anchor:
			count += 1
	return count


func cancel_build_at(target: Vector2i) -> BuildJob:
	if not _build_targets.has(target):
		return null
	var job: BuildJob = _build_targets[target]
	for cell in job.footprint:
		_build_targets.erase(cell)
	pending.erase(job)
	_unindex_job(job)
	job_cancelled.emit(job)
	return job


func has_build_at(target: Vector2i) -> bool:
	return _build_targets.has(target)


func build_job_at(target: Vector2i) -> BuildJob:
	return _build_targets.get(target) as BuildJob


func force_claim(job: Job, worker: Node) -> bool:
	if job == null or worker == null or not is_active(job):
		return false
	if job.claimed_by != null and job.claimed_by != worker:
		job.claimed_by = null
		job_cancelled.emit(job)
	job.claimed_by = worker
	return true


## Returns the closest unclaimed job from `worker_grid` (Chebyshev), or null.
## Marks the returned job as claimed by `worker`. Scans the 3x3 chunk
## neighborhood first; falls back to the global pending list only if the
## neighborhood is empty.
func claim_next_for(worker: Node, worker_grid: Vector2i) -> Job:
	var now_msec: int = Time.get_ticks_msec()
	var best: Job = _best_job_in_neighborhood(worker_grid, now_msec)
	if best == null:
		best = _best_job_global(worker_grid, now_msec)
	if best != null:
		best.claimed_by = worker
	return best


func _best_job_in_neighborhood(worker_grid: Vector2i, now_msec: int) -> Job:
	var worker_chunk: Vector2i = Chunk.grid_to_chunk(worker_grid)
	var best: Job = null
	var best_dist: int = 0x7fffffff
	var best_priority: int = 0x7fffffff
	for cy in range(worker_chunk.y - NEAR_CHUNK_RADIUS, worker_chunk.y + NEAR_CHUNK_RADIUS + 1):
		for cx in range(worker_chunk.x - NEAR_CHUNK_RADIUS, worker_chunk.x + NEAR_CHUNK_RADIUS + 1):
			var key := Vector2i(cx, cy)
			if not _pending_by_chunk.has(key):
				continue
			for job in _pending_by_chunk[key] as Array:
				if not _job_is_claimable(job, now_msec):
					continue
				var t: Vector2i = _target_grid_of(job)
				var d: int = maxi(absi(t.x - worker_grid.x), absi(t.y - worker_grid.y))
				var priority: int = _priority_of(job)
				if priority < best_priority or (priority == best_priority and d < best_dist):
					best = job
					best_dist = d
					best_priority = priority
	return best


## Fallback when the 3x3 chunk neighborhood is empty. Instead of scanning every
## pending job (O(jobs), which dominates frame time once a big designation drops
## hundreds), find the nearest non-empty chunk via the chunk index and scan only
## chunks within one ring of it. Cost is O(non-empty chunks + jobs in the nearest
## cluster). Workers therefore prefer the closest cluster of work.
func _best_job_global(worker_grid: Vector2i, now_msec: int) -> Job:
	if _pending_by_chunk.is_empty():
		return null
	var worker_chunk: Vector2i = Chunk.grid_to_chunk(worker_grid)
	var nearest_chunk_dist: int = 0x7fffffff
	for key in _pending_by_chunk:
		var cc: Vector2i = key
		var cd: int = maxi(absi(cc.x - worker_chunk.x), absi(cc.y - worker_chunk.y))
		if cd < nearest_chunk_dist:
			nearest_chunk_dist = cd
	# Include one extra ring so a job just across a chunk boundary isn't missed.
	var max_chunk_dist: int = nearest_chunk_dist + 1
	var best: Job = null
	var best_dist: int = 0x7fffffff
	var best_priority: int = 0x7fffffff
	for key in _pending_by_chunk:
		var cc: Vector2i = key
		var cd: int = maxi(absi(cc.x - worker_chunk.x), absi(cc.y - worker_chunk.y))
		if cd > max_chunk_dist:
			continue
		for job in _pending_by_chunk[key] as Array:
			if not _job_is_claimable(job, now_msec):
				continue
			var t: Vector2i = _target_grid_of(job)
			var d: int = maxi(absi(t.x - worker_grid.x), absi(t.y - worker_grid.y))
			var priority: int = _priority_of(job)
			if priority < best_priority or (priority == best_priority and d < best_dist):
				best = job
				best_dist = d
				best_priority = priority
	return best


static func _job_is_claimable(job: Job, now_msec: int) -> bool:
	if job.claimed_by != null:
		return false
	if job.blocked_until_msec > now_msec:
		return false
	return true


## Release a claimed job back to the pool (worker couldn't path, etc.).
func release(job: Job) -> void:
	job.claimed_by = null


func is_active(job: Job) -> bool:
	return pending.has(job)


## Mark a job done and remove it. Also clears any per-target index.
func complete(job: Job) -> void:
	pending.erase(job)
	_unindex_job(job)
	if job is MineJob:
		_mine_targets.erase((job as MineJob).target)
	elif job is BuildJob:
		for cell in (job as BuildJob).footprint:
			_build_targets.erase(cell)
	elif job.kind == Job.Kind.SCRAPE_RUST:
		_scrape_targets.erase(job.get("target") as Vector2i)
	elif job.kind == Job.Kind.SCRAPE_BIOMASS:
		_scrape_biomass_targets.erase(job.get("target") as Vector2i)
	elif job is OperateStructureJob:
		_operation_targets.erase((job as OperateStructureJob).anchor)
	job_completed.emit(job)


func pending_count() -> int:
	return pending.size()


## Cancel an arbitrary job reference, cleaning up per-type indexes the same
## way `complete` does. Returns true if the job was removed. For HaulJobs
## the stockpile reservation is released via the StockpileZone API so the
## reserved cell becomes available again.
func cancel_job(job: Job) -> bool:
	if job == null or not pending.has(job):
		return false
	if job is MineJob:
		_mine_targets.erase((job as MineJob).target)
	elif job is BuildJob:
		for cell in (job as BuildJob).footprint:
			_build_targets.erase(cell)
	elif job is OperateStructureJob:
		_operation_targets.erase((job as OperateStructureJob).anchor)
	elif job is HaulJob:
		var haul := job as HaulJob
		if haul.dropoff_zone != null and is_instance_valid(haul.dropoff_zone) \
				and haul.dropoff_zone.has_method("unreserve"):
			haul.dropoff_zone.call("unreserve", haul.dropoff)
		if haul.item != null and is_instance_valid(haul.item) \
				and "reserved_by" in haul.item:
			haul.item.set("reserved_by", null)
	elif job.kind == Job.Kind.SCRAPE_RUST:
		_scrape_targets.erase(job.get("target") as Vector2i)
	elif job.kind == Job.Kind.SCRAPE_BIOMASS:
		_scrape_biomass_targets.erase(job.get("target") as Vector2i)
	pending.erase(job)
	_unindex_job(job)
	job_cancelled.emit(job)
	return true


## Human-readable label for a job, used by the jobs dropdown UI.
static func describe_job(job: Job) -> String:
	if job == null:
		return ""
	if job is MineJob:
		var m := job as MineJob
		return "Mine (%d,%d)" % [m.target.x, m.target.y]
	if job is BuildJob:
		var b := job as BuildJob
		return "Build %s (%d,%d)" % [BuildBlueprint.display_name(b.blueprint_id), b.anchor.x, b.anchor.y]
	if job is HaulJob:
		var h := job as HaulJob
		var item_name: String = "item"
		if h.item != null and is_instance_valid(h.item) and h.item is Item:
			var it := h.item as Item
			item_name = Item.stack_label(it.kind, it.count)
		return "Haul %s -> (%d,%d)" % [item_name, h.dropoff.x, h.dropoff.y]
	if job is CraftJob:
		var c := job as CraftJob
		return "Craft %s @ (%d,%d)" % [Item.kind_name(c.object_kind), c.station_anchor.x, c.station_anchor.y]
	if job is OperateStructureJob:
		var o := job as OperateStructureJob
		return "Operate %s (%d,%d)" % [BuildBlueprint.display_name(o.structure_id), o.anchor.x, o.anchor.y]
	if job.kind == Job.Kind.SCRAPE_RUST:
		var t: Vector2i = job.get("target") as Vector2i
		return "Scrape rust (%d,%d)" % [t.x, t.y]
	if job.kind == Job.Kind.SCRAPE_BIOMASS:
		var tg: Vector2i = job.get("target") as Vector2i
		return "Scrape biomass (%d,%d)" % [tg.x, tg.y]
	return "Job"


## Save layer: snapshot the player-issued designations (mine/build/scrape/craft).
## Haul and operate jobs are intentionally omitted — they regenerate from the
## restored loose items / stockpiles and the StructureManager production tick.
## Claim ownership and in-progress timers are dropped; jobs come back fresh.
func capture_save() -> Dictionary:
	var mine: Array = []
	var build: Array = []
	var scrape_rust: Array = []
	var scrape_biomass: Array = []
	var craft: Array = []
	for job in pending:
		if job is MineJob:
			mine.append((job as MineJob).target)
		elif job is BuildJob:
			var b := job as BuildJob
			build.append([b.anchor, b.blueprint_id, b.rotation])
		elif job is CraftJob:
			var c := job as CraftJob
			craft.append([c.station_anchor, c.object_kind])
		elif job.kind == Job.Kind.SCRAPE_RUST:
			scrape_rust.append(job.get("target") as Vector2i)
		elif job.kind == Job.Kind.SCRAPE_BIOMASS:
			scrape_biomass.append(job.get("target") as Vector2i)
	return {
		"mine": mine,
		"build": build,
		"scrape_rust": scrape_rust,
		"scrape_biomass": scrape_biomass,
		"craft": craft,
	}


func restore_save(data: Dictionary) -> void:
	for t in data.get("mine", []) as Array:
		add_mine_job(t as Vector2i)
	for e in data.get("build", []) as Array:
		add_build_job(e[0] as Vector2i, int(e[1]), int(e[2]))
	for t in data.get("scrape_rust", []) as Array:
		add_scrape_rust_job(t as Vector2i)
	for t in data.get("scrape_biomass", []) as Array:
		add_scrape_biomass_job(t as Vector2i)
	for e in data.get("craft", []) as Array:
		add_craft_job(e[0] as Vector2i, int(e[1]))


func _index_job(job: Job) -> void:
	var target_grid: Vector2i = _target_grid_of(job)
	var chunk: Vector2i = Chunk.grid_to_chunk(target_grid)
	if not _pending_by_chunk.has(chunk):
		_pending_by_chunk[chunk] = []
	(_pending_by_chunk[chunk] as Array).append(job)
	_job_indexed_chunk[job] = chunk


func _unindex_job(job: Job) -> void:
	if not _job_indexed_chunk.has(job):
		return
	var chunk: Vector2i = _job_indexed_chunk[job] as Vector2i
	_job_indexed_chunk.erase(job)
	
	if not _pending_by_chunk.has(chunk):
		return
	var arr: Array = _pending_by_chunk[chunk] as Array
	arr.erase(job)
	if arr.is_empty():
		_pending_by_chunk.erase(chunk)


static func _target_grid_of(job: Job) -> Vector2i:
	if job is MineJob:
		return (job as MineJob).target
	if job is BuildJob:
		return (job as BuildJob).anchor
	if job is HaulJob:
		var h := job as HaulJob
		if h.item != null and h.item.has_method("get_grid"):
			return h.item.call("get_grid") as Vector2i
		return h.dropoff
	if job is CraftJob:
		return (job as CraftJob).station_anchor
	if job is OperateStructureJob:
		return (job as OperateStructureJob).anchor
	if job.kind == Job.Kind.SCRAPE_RUST:
		return job.get("target") as Vector2i
	if job.kind == Job.Kind.SCRAPE_BIOMASS:
		return job.get("target") as Vector2i
	return Vector2i.ZERO


static func _priority_of(job: Job) -> int:
	if job is CraftJob:
		return 4
	if job is BuildJob:
		return 8
	if job is OperateStructureJob:
		return 12
	if job is HaulJob:
		return 16
	if job is MineJob:
		return 40
	if job.kind == Job.Kind.SCRAPE_RUST or job.kind == Job.Kind.SCRAPE_BIOMASS:
		return 100
	return 50
