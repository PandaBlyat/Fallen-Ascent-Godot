extends Node
##
## Bootstrap. Picks a world seed (random by default; override via the
## `--seed=<int>` command-line argument for reproducible dev runs) and
## hands off to the world map.
##

func _ready() -> void:
	GameState.set_world_seed(_resolve_seed())
	GameState.set_game_speed(1.0)
	get_tree().change_scene_to_file("res://scenes/world/WorldMap.tscn")


func _resolve_seed() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return arg.substr("--seed=".length()).to_int()
	return randi()
