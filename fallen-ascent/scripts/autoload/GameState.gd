extends Node
##
## Global ambient state. Read freely; write only through the setters below
## so that EventBus signals fire and dependent systems stay in sync.
##

var world_seed: int = 0
var selected_site: Resource = null
var game_speed: float = 1.0


func set_world_seed(value: int) -> void:
	world_seed = value


func set_selected_site(site: Resource) -> void:
	selected_site = site
	EventBus.site_selected.emit(site)


func set_game_speed(value: float) -> void:
	var clamped: float = maxf(value, 0.0)
	if is_equal_approx(clamped, game_speed):
		return
	game_speed = clamped
	Engine.time_scale = clamped
	EventBus.game_speed_changed.emit(clamped)


func is_paused() -> bool:
	return is_zero_approx(game_speed)
