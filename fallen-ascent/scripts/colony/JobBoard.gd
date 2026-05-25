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
## Chunk-coord -> Array[Job]. Lets claim_next_for scan only nearby
## chunks first instead of the full pending list each poll.
var _pending_by_chunk: Dictionary = {}

const SCRAPE_RUST_JOB_SCRIPT: Script = preload("res://scripts/colony/jobs/ScrapeRustJob.gd")
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


func _best_job_global(worker_grid: Vector2i, now_msec: int) -> Job:
	var best: Job = null
	var best_dist: int = 0x7fffffff
	var best_priority: int = 0x7fffffff
	for job in pending:
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
	job_completed.emit(job)


func pending_count() -> int:
	return pending.size()


func _index_job(job: Job) -> void:
	var chunk: Vector2i = Chunk.grid_to_chunk(_target_grid_of(job))
	if not _pending_by_chunk.has(chunk):
		_pending_by_chunk[chunk] = []
	(_pending_by_chunk[chunk] as Array).append(job)


func _unindex_job(job: Job) -> void:
	var chunk: Vector2i = Chunk.grid_to_chunk(_target_grid_of(job))
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
	if job.kind == Job.Kind.SCRAPE_RUST:
		return job.get("target") as Vector2i
	return Vector2i.ZERO


static func _priority_of(job: Job) -> int:
	if job.kind == Job.Kind.SCRAPE_RUST:
		return 20
	return 0
