class_name UiStyle
##
## Shared UI styling helpers. The whole game's chrome is skinned from the
## placeholder panel PNGs (see CLAUDE.md); menus that build plain Godot Buttons
## (main menu, settings) used to fall back to the engine's default button look,
## which clashed with the rest of the HUD. `button_theme()` returns a cached
## Theme that skins Button + OptionButton with `worker_card.png` so those menus
## match. It's built off the project's Orbitron theme so the font carries over.
##

const WORKER_CARD_PATH: String = "res://resources/ui/panels/worker_card.png"
const ORBITRON_THEME_PATH: String = "res://resources/ui/orbitron_theme.tres"

## Lazily built + cached; the same Theme instance is shared by every menu.
static var _button_theme: Theme = null


## A Theme skinning Button/OptionButton with the worker-card texture. Assign it
## to a menu's root Control (`theme = UiStyle.button_theme()`) and every button
## below inherits the look while other widgets fall through to the project theme.
static func button_theme() -> Theme:
	if _button_theme != null:
		return _button_theme
	var theme: Theme
	if ResourceLoader.exists(ORBITRON_THEME_PATH):
		theme = (load(ORBITRON_THEME_PATH) as Theme).duplicate()
	else:
		theme = Theme.new()
	var tex: Texture2D = _worker_card_texture()
	if tex != null:
		_style_button_type(theme, "Button", tex)
		_style_button_type(theme, "OptionButton", tex)
	_button_theme = theme
	return theme


static func _worker_card_texture() -> Texture2D:
	if not ResourceLoader.exists(WORKER_CARD_PATH):
		return null
	return load(WORKER_CARD_PATH) as Texture2D


static func _box(tex: Texture2D, tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = 16.0
	style.texture_margin_top = 16.0
	style.texture_margin_right = 16.0
	style.texture_margin_bottom = 16.0
	style.modulate_color = tint
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


static func _style_button_type(theme: Theme, type_name: String, tex: Texture2D) -> void:
	theme.set_stylebox("normal", type_name, _box(tex, Color(0.82, 0.88, 0.92)))
	theme.set_stylebox("hover", type_name, _box(tex, Color(1.0, 1.0, 1.0)))
	theme.set_stylebox("pressed", type_name, _box(tex, Color(0.70, 0.80, 0.72)))
	theme.set_stylebox("disabled", type_name, _box(tex, Color(0.45, 0.47, 0.50, 0.75)))
	theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	theme.set_color("font_color", type_name, Color(0.90, 0.94, 0.96))
	theme.set_color("font_hover_color", type_name, Color(1.0, 1.0, 1.0))
	theme.set_color("font_pressed_color", type_name, Color(1.0, 1.0, 1.0))
	theme.set_color("font_disabled_color", type_name, Color(0.55, 0.58, 0.60))
