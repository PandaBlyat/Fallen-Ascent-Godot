extends Node
##
## Central audio hub. Manages ambient background loops, UI one-shot sounds,
## and positional world SFX (combat hits, mine completion).
##
## Positional AudioStreamPlayer2D max_distance scales WITH camera zoom so
## sounds cover roughly the same SCREEN footprint at any zoom level.
## At low zoom (zoomed out) max_distance shrinks, making individual worker
## sounds inaudible — intentional, as there are too many to hear at once.
##

const AMBIENCE_A: AudioStream = preload("res://industrial_ambience_6minutes.mp3")
const AMBIENCE_B: AudioStream = preload("res://industrial_background_noise_PUT_LOW_VOLUME.mp3")
const BOT_HIT_SFX: AudioStream = preload("res://bot_hit_sound.mp3")
const PLACING_SFX: AudioStream = preload("res://placing_sound.mp3")
const BUTTON_SFX: AudioStream = preload("res://button_press_sound.mp3")
const MINE_THUMP_SFX: AudioStream = preload("res://satisfying_thump.mp3")
const ZOOM_IN_SFX: AudioStream = preload("res://zoom_in_sound.mp3")
const ZOOM_OUT_SFX: AudioStream = preload("res://zoom_out_sound.mp3")
const MOVE_HERE_SFX: AudioStream = preload("res://move_here_sound.mp3")

## Ambience is on the dedicated Ambient bus, not Music.
const AMBIENCE_A_VOLUME_DB: float = -10.0
const AMBIENCE_B_VOLUME_DB: float = -20.0
const BOT_HIT_VOLUME_DB: float = -6.0
const PLACING_VOLUME_DB: float = -4.0
const BUTTON_VOLUME_DB: float = -8.0
const MINE_THUMP_VOLUME_DB: float = -5.0
const ZOOM_VOLUME_DB: float = -10.0
const MOVE_HERE_VOLUME_DB: float = -8.0

## Positional sound audible radius (world pixels) at camera zoom 1.0.
## Multiplied by zoom so zoomed-out play has a shorter reach.
const BASE_MAX_DIST_PX: float = 500.0
const POOL_SIZE: int = 4

var _ambience_a: AudioStreamPlayer
var _ambience_b: AudioStreamPlayer
var _button_player: AudioStreamPlayer
var _placing_player: AudioStreamPlayer
var _zoom_in_player: AudioStreamPlayer
var _zoom_out_player: AudioStreamPlayer
var _move_here_player: AudioStreamPlayer
var _hit_pool: Array[AudioStreamPlayer2D] = []
var _thump_pool: Array[AudioStreamPlayer2D] = []

## Read by Worker to initialise its own AudioStreamPlayer2D max_distance.
var current_max_dist: float = BASE_MAX_DIST_PX


func _ready() -> void:
	_setup_ambience()
	_setup_ui_players()
	_setup_pools()
	EventBus.combat_hit.connect(_on_combat_hit)
	EventBus.camera_moved.connect(_on_camera_moved)


func _setup_ambience() -> void:
	_ambience_a = AudioStreamPlayer.new()
	_ambience_a.stream = AMBIENCE_A
	_ambience_a.volume_db = AMBIENCE_A_VOLUME_DB
	_ambience_a.bus = &"Ambient"
	add_child(_ambience_a)
	_ambience_a.finished.connect(func() -> void: _ambience_a.play())
	_ambience_a.play()

	_ambience_b = AudioStreamPlayer.new()
	_ambience_b.stream = AMBIENCE_B
	_ambience_b.volume_db = AMBIENCE_B_VOLUME_DB
	_ambience_b.bus = &"Ambient"
	add_child(_ambience_b)
	_ambience_b.finished.connect(func() -> void: _ambience_b.play())
	_ambience_b.play()


func _setup_ui_players() -> void:
	_button_player = AudioStreamPlayer.new()
	_button_player.stream = BUTTON_SFX
	_button_player.volume_db = BUTTON_VOLUME_DB
	_button_player.bus = &"SFX"
	add_child(_button_player)

	_placing_player = AudioStreamPlayer.new()
	_placing_player.stream = PLACING_SFX
	_placing_player.volume_db = PLACING_VOLUME_DB
	_placing_player.bus = &"SFX"
	add_child(_placing_player)

	_zoom_in_player = AudioStreamPlayer.new()
	_zoom_in_player.stream = ZOOM_IN_SFX
	_zoom_in_player.volume_db = ZOOM_VOLUME_DB
	_zoom_in_player.bus = &"SFX"
	add_child(_zoom_in_player)

	_zoom_out_player = AudioStreamPlayer.new()
	_zoom_out_player.stream = ZOOM_OUT_SFX
	_zoom_out_player.volume_db = ZOOM_VOLUME_DB
	_zoom_out_player.bus = &"SFX"
	add_child(_zoom_out_player)

	_move_here_player = AudioStreamPlayer.new()
	_move_here_player.stream = MOVE_HERE_SFX
	_move_here_player.volume_db = MOVE_HERE_VOLUME_DB
	_move_here_player.bus = &"SFX"
	add_child(_move_here_player)


func _setup_pools() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.stream = BOT_HIT_SFX
		p.volume_db = BOT_HIT_VOLUME_DB
		p.bus = &"SFX"
		p.max_distance = BASE_MAX_DIST_PX
		add_child(p)
		_hit_pool.append(p)

	for _i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.stream = MINE_THUMP_SFX
		p.volume_db = MINE_THUMP_VOLUME_DB
		p.bus = &"SFX"
		p.max_distance = BASE_MAX_DIST_PX
		add_child(p)
		_thump_pool.append(p)


func play_button_press() -> void:
	_button_player.stop()
	_button_player.play()


func play_placing() -> void:
	_placing_player.stop()
	_placing_player.play()


func play_zoom_in() -> void:
	_zoom_in_player.stop()
	_zoom_in_player.play()


func play_zoom_out() -> void:
	_zoom_out_player.stop()
	_zoom_out_player.play()


func play_move_here() -> void:
	_move_here_player.stop()
	_move_here_player.play()


func play_mine_complete(world_pos: Vector2) -> void:
	var p: AudioStreamPlayer2D = _take_from_pool(_thump_pool)
	if p == null:
		return
	p.global_position = world_pos
	p.play()


func _on_combat_hit(_attacker: Node, target: Node, _damage: float) -> void:
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return
	var p: AudioStreamPlayer2D = _take_from_pool(_hit_pool)
	if p == null:
		return
	p.global_position = (target as Node2D).global_position
	p.play()


func _on_camera_moved(_world_pos: Vector2, zoom: Vector2) -> void:
	var zoom_factor: float = (zoom.x + zoom.y) * 0.5
	# Scale max_distance WITH zoom: zoomed out = smaller radius = worker sounds fade
	current_max_dist = BASE_MAX_DIST_PX * clampf(zoom_factor, 0.1, 2.0)
	for p: AudioStreamPlayer2D in _hit_pool:
		p.max_distance = current_max_dist
	for p: AudioStreamPlayer2D in _thump_pool:
		p.max_distance = current_max_dist


func _take_from_pool(pool: Array[AudioStreamPlayer2D]) -> AudioStreamPlayer2D:
	for p: AudioStreamPlayer2D in pool:
		if not p.playing:
			return p
	return pool[0] if not pool.is_empty() else null
