class_name MineJob
extends Job
##
## "Mine the wall tile at `target`." Worker stands on an adjacent walkable
## cell and accumulates `progress` until DURATION seconds elapsed.
##

const DURATION: float = 2.0

var target: Vector2i = Vector2i.ZERO
var progress: float = 0.0
var blocked_until_msec: int = 0


func _init(t: Vector2i = Vector2i.ZERO) -> void:
	kind = Kind.MINE
	target = t


func block_briefly(seconds: float = 1.25) -> void:
	blocked_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
