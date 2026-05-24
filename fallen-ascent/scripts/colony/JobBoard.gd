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

const SCRAPE_RUST_JOB_SCRIPT: Script = preload("res://scripts/colony/jobs/ScrapeRustJob.gd")


func add_mine_job(target: Vector2i) -> MineJob:
	if _mine_targets.has(target):
		return _mine_targets[target] as MineJob
	var job := MineJob.new(target)
	pending.append(job)
	_mine_targets[target] = job
	job_added.emit(job)
	return job


func cancel_mine_at(target: Vector2i) -> void:
	if not _mine_targets.has(target):
		return
	var job: MineJob = _mine_targets[target]
	_mine_targets.erase(target)
	pending.erase(job)
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
	job_added.emit(job)
	return job


func cancel_scrape_rust_at(target: Vector2i) -> void:
	if not _scrape_targets.has(target):
		return
	var job: Job = _scrape_targets[target] as Job
	_scrape_targets.erase(target)
	pending.erase(job)
	job_cancelled.emit(job)


func has_scrape_rust_at(target: Vector2i) -> bool:
	return _scrape_targets.has(target)


func scrape_rust_count() -> int:
	return _scrape_targets.size()


func add_haul_job(item: Node, zone: Node, cell: Vector2i) -> HaulJob:
	var job := HaulJob.new(item, zone, cell)
	pending.append(job)
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
	job_added.emit(job)
	return job


func cancel_build_at(target: Vector2i) -> BuildJob:
	if not _build_targets.has(target):
		return null
	var job: BuildJob = _build_targets[target]
	for cell in job.footprint:
		_build_targets.erase(cell)
	pending.erase(job)
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
## Marks the returned job as claimed by `worker`.
func claim_next_for(worker: Node, worker_grid: Vector2i) -> Job:
	var best: Job = null
	var best_dist: int = 0x7fffffff
	var best_priority: int = 0x7fffffff
	var now_msec: int = Time.get_ticks_msec()
	for job in pending:
		if job.claimed_by != null:
			continue
		if job is BuildJob and (job as BuildJob).blocked_until_msec > now_msec:
			continue
		var t: Vector2i = _target_grid_of(job)
		var d: int = maxi(absi(t.x - worker_grid.x), absi(t.y - worker_grid.y))
		var priority: int = _priority_of(job)
		if priority < best_priority or (priority == best_priority and d < best_dist):
			best = job
			best_dist = d
			best_priority = priority
	if best != null:
		best.claimed_by = worker
	return best


## Release a claimed job back to the pool (worker couldn't path, etc.).
func release(job: Job) -> void:
	job.claimed_by = null


func is_active(job: Job) -> bool:
	return pending.has(job)


## Mark a job done and remove it. Also clears any per-target index.
func complete(job: Job) -> void:
	pending.erase(job)
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
