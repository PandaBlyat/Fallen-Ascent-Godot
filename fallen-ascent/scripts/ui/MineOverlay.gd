class_name MineOverlay
extends Node2D
##
## Translucent red square per pending mine designation. Listens to JobBoard
## signals so it only redraws when designations change, not every frame.
##

const FILL := Color(0.85, 0.2, 0.2, 0.35)
const BORDER := Color(1.0, 0.3, 0.3, 0.7)

@export var job_board_path: NodePath

var _job_board: JobBoard


func _ready() -> void:
	_job_board = get_node(job_board_path) as JobBoard
	_job_board.job_added.connect(_on_jobs_changed)
	_job_board.job_cancelled.connect(_on_jobs_changed)
	_job_board.job_completed.connect(_on_jobs_changed)


func _on_jobs_changed(_job: Job) -> void:
	queue_redraw()


func _draw() -> void:
	for job in _job_board.pending:
		if not (job is MineJob):
			continue
		var t: Vector2i = (job as MineJob).target
		var origin := Vector2(t.x * Chunk.TILE_PIXELS, t.y * Chunk.TILE_PIXELS)
		var r := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
		draw_rect(r, FILL)
		draw_rect(r, BORDER, false, 1.0)
