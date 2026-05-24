class_name MineOverlay
extends Node2D
##
## Translucent overlay per pending designation. One color per job kind.
## Listens to JobBoard signals so it only redraws when designations change,
## not every frame.
##

const MINE_FILL := Color(0.85, 0.2, 0.2, 0.35)
const MINE_BORDER := Color(1.0, 0.3, 0.3, 0.7)
const BUILD_FILL := Color(0.3, 0.55, 0.95, 0.32)
const BUILD_BORDER := Color(0.5, 0.75, 1.0, 0.8)

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
		if job is MineJob:
			_draw_cell((job as MineJob).target, MINE_FILL, MINE_BORDER)
		elif job is BuildJob:
			_draw_cell((job as BuildJob).target, BUILD_FILL, BUILD_BORDER)


func _draw_cell(t: Vector2i, fill: Color, border: Color) -> void:
	var origin := Vector2(t.x * Chunk.TILE_PIXELS, t.y * Chunk.TILE_PIXELS)
	var r := Rect2(origin, Vector2(Chunk.TILE_PIXELS, Chunk.TILE_PIXELS))
	draw_rect(r, fill)
	draw_rect(r, border, false, 1.0)
