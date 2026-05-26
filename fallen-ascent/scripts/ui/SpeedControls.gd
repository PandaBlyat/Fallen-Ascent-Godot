extends HBoxContainer
##
## Bottom-of-screen speed buttons: pause / 1× / 2× / 3× / 10×.
## Buttons drive GameState.set_game_speed; hotkeys 0/1/2/3/4 do the same.
## The currently-active button is visually highlighted via `button_pressed`.
##

const SPEEDS := [0.0, 1.0, 2.0, 3.0, 10.0]
const LABELS := ["||", "1x", "2x", "3x", "10x"]
const TOOLTIPS := [
	"Pause\nKey: 0 or Space",
	"Normal speed\nKey: 1",
	"Fast speed\nKey: 2",
	"Max speed\nKey: 3",
	"Extreme speed\nKey: 4",
]
const COLOR_BG := Color(0.045, 0.052, 0.06, 0.88)
const COLOR_BG_HOVER := Color(0.14, 0.16, 0.18, 0.94)
const COLOR_ACTIVE := Color(0.25, 0.20, 0.12, 1.0)
const COLOR_BORDER := Color(0.33, 0.36, 0.39, 0.62)
const COLOR_ACCENT := Color(0.96, 0.58, 0.16, 1.0)
const COLOR_TEXT := Color(0.90, 0.93, 0.91, 1.0)

var _buttons: Array[Button] = []
var _last_play_speed: float = 1.0


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	for i in SPEEDS.size():
		var b: Button = Button.new()
		b.text = LABELS[i]
		b.tooltip_text = TOOLTIPS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(60, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_stylebox_override("normal", _button_style(COLOR_BG, COLOR_BORDER))
		b.add_theme_stylebox_override("hover", _button_style(COLOR_BG_HOVER, COLOR_ACCENT))
		b.add_theme_stylebox_override("pressed", _button_style(COLOR_ACTIVE, COLOR_ACCENT))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", COLOR_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
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
	elif event.is_action_pressed("speed_10x"):
		GameState.set_game_speed(SPEEDS[4])


func _on_pressed(idx: int) -> void:
	GameState.set_game_speed(SPEEDS[idx])


func _on_speed_changed(speed: float) -> void:
	if speed > 0.0:
		_last_play_speed = speed
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(is_equal_approx(speed, SPEEDS[i]))


func _button_style(fill: Color, border: Color) -> StyleBox:
	const PANEL_PATH := "res://resources/ui/panels/selection_panel.png"
	if ResourceLoader.exists(PANEL_PATH):
		var tex: Texture2D = load(PANEL_PATH) as Texture2D
		if tex != null:
			var tex_style := StyleBoxTexture.new()
			tex_style.texture = tex
			tex_style.texture_margin_left = 16.0
			tex_style.texture_margin_top = 16.0
			tex_style.texture_margin_right = 16.0
			tex_style.texture_margin_bottom = 16.0
			tex_style.content_margin_left = 14.0
			tex_style.content_margin_top = 8.0
			tex_style.content_margin_right = 14.0
			tex_style.content_margin_bottom = 8.0
			# Tint the shared panel art so the pause / active / hover states stay
			# distinguishable without authoring three separate PNGs.
			tex_style.modulate_color = fill.lerp(Color.WHITE, 0.35)
			return tex_style
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style
