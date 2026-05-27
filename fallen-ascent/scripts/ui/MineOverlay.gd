class_name MineOverlay
extends Node2D
##
## Border-only overlay per pending designation. One color per job kind.
## Listens to JobBoard signals so it only redraws when designations change,
## not every frame.
##

const MINE_BORDER := Color(1.0, 0.3, 0.3, 0.7)
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
	var mine_cells := {}
	var build_cells := {}

	# Gather all coordinates to check adjacency
	for job in _job_board.pending:
		if job is MineJob:
			mine_cells[(job as MineJob).target] = true
		elif job is BuildJob:
			var build := job as BuildJob
			for cell in build.footprint:
				build_cells[cell] = true

	# Draw only the borders for each group
	_draw_merged_border(mine_cells, MINE_BORDER)
	_draw_merged_border(build_cells, BUILD_BORDER)


func _draw_merged_border(cells: Dictionary, border: Color) -> void:
	var tile_size := float(Chunk.TILE_PIXELS)

	for cell in cells:
		var origin := Vector2(cell.x * tile_size, cell.y * tile_size)
		
		# Define the four corners of the current tile
		var tl := origin
		var tr := origin + Vector2(tile_size, 0)
		var bl := origin + Vector2(0, tile_size)
		var br := origin + Vector2(tile_size, tile_size)

		# Top edge
		if not cells.has(cell + Vector2i.UP):
			draw_line(tl, tr, border, 1.0)
		
		# Bottom edge
		if not cells.has(cell + Vector2i.DOWN):
			draw_line(bl, br, border, 1.0)
		
		# Left edge
		if not cells.has(cell + Vector2i.LEFT):
			draw_line(tl, bl, border, 1.0)
		
		# Right edge
		if not cells.has(cell + Vector2i.RIGHT):
			draw_line(tr, br, border, 1.0)
