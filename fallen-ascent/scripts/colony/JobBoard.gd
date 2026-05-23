class_name JobBoard
extends Node
##
## Holds the queue of unclaimed and in-flight jobs for one colony site.
## Workers pull from `claim_next_for`; designators add via `add_mine_job`
## and `add_haul_job`. Local signals only — no EventBus traffic.
##

signal job_added(job: Job)
signal job_completed(job: Job)
signal job_cancelled(job: Job)

var pending: Array[Job] = []
var _mine_targets: Dictionary = {}   ## Vector2i -> MineJob, for fast cancel/dedup


func add_mine_job(target: Vector2i) -> void:
	if _mine_targets.has(target):
		return
	var job := MineJob.new(target)
	pending.append(job)
	_mine_targets[target] = job
	job_added.emit(job)


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


func add_haul_job(item: Node, zone: Node, cell: Vector2i) -> void:
	var job := HaulJob.new(item, zone, cell)
	pending.append(job)
	job_added.emit(job)


## Returns the closest unclaimed job from `worker_grid` (Chebyshev), or null.
## Marks the returned job as claimed by `worker`.
func claim_next_for(worker: Node, worker_grid: Vector2i) -> Job:
	var best: Job = null
	var best_dist: int = 0x7fffffff
	for job in pending:
		if job.claimed_by != null:
			continue
		var t: Vector2i = _target_grid_of(job)
		var d: int = maxi(absi(t.x - worker_grid.x), absi(t.y - worker_grid.y))
		if d < best_dist:
			best = job
			best_dist = d
	if best != null:
		best.claimed_by = worker
	return best


## Release a claimed job back to the pool (worker couldn't path, etc.).
func release(job: Job) -> void:
	job.claimed_by = null


## Mark a job done and remove it. Also clears any mine-target index.
func complete(job: Job) -> void:
	pending.erase(job)
	if job is MineJob:
		_mine_targets.erase((job as MineJob).target)
	job_completed.emit(job)


func pending_count() -> int:
	return pending.size()


static func _target_grid_of(job: Job) -> Vector2i:
	if job is MineJob:
		return (job as MineJob).target
	if job is HaulJob:
		var h := job as HaulJob
		if h.item != null and h.item.has_method("get_grid"):
			return h.item.call("get_grid") as Vector2i
		return h.dropoff
	return Vector2i.ZERO
