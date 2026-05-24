extends HBoxContainer
##
## Bottom-of-screen speed buttons: pause / 1× / 2× / 3×.
## Buttons drive GameState.set_game_speed; hotkeys 0/1/2/3 do the same.
## The currently-active button is visually highlighted via `button_pressed`.
##

const SPEEDS := [0.0, 1.0, 2.0, 3.0]
const LABELS := ["||", "1x", "2x", "3x"]

var _buttons: Array[Button] = []
var _last_play_speed: float = 1.0


func _ready() -> void:
	for i in SPEEDS.size():
		var b: Button = Button.new()
		b.text = LABELS[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 32)
		b.pressed.connect(_on_pressed.bind(i))
		add_child(b)
		_buttons.append(b)

	EventBus.game_speed_changed.connect(_on_speed_changed)
	_on_speed_changed(GameState.game_speed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_toggle"):
		if GameState.is_paused():
			GameState.set_game_speed(_last_play_speed)
		else:
			GameState.set_game_speed(SPEEDS[0])
	elif event.is_action_pressed("speed_pause"):
		GameState.set_game_speed(SPEEDS[0])
	elif event.is_action_pressed("speed_1x"):
		GameState.set_game_speed(SPEEDS[1])
	elif event.is_action_pressed("speed_2x"):
		GameState.set_game_speed(SPEEDS[2])
	elif event.is_action_pressed("speed_3x"):
		GameState.set_game_speed(SPEEDS[3])


func _on_pressed(idx: int) -> void:
	GameState.set_game_speed(SPEEDS[idx])


func _on_speed_changed(speed: float) -> void:
	if speed > 0.0:
		_last_play_speed = speed
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(is_equal_approx(speed, SPEEDS[i]))
