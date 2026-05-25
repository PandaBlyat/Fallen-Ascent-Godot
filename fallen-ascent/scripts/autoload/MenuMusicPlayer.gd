extends Node
##
## Main-menu music lives here so scene changes do not cut off current track.
##

const MENU_TRACK: AudioStream = preload("res://Rust in the Vault.mp3")

var _player: AudioStreamPlayer
var _playing: bool = false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.stream = MENU_TRACK
	_player.bus = &"Music"
	add_child(_player)
	_player.finished.connect(_on_finished)


func play_once_from_start() -> void:
	if _playing and _player.playing:
		return
	_player.stop()
	_player.play()
	_playing = true


func _on_finished() -> void:
	_playing = false
