extends Node

const COLOR_BG := Color("1a1a2e")
const COLOR_PANEL := Color("16213e")
const COLOR_ACCENT := Color("e94560")
const COLOR_ACCENT_HOVER := Color("ff6b81")
const COLOR_TEXT := Color("f1f1f1")

const BORDER_WIDTH := 2
const CORNER_RADIUS := 0

const PIXEL_FONT_PATH := "res://assets/fonts/Kenney Pixel.ttf"

var theme: Theme

func _ready() -> void:
	theme = build_theme()

func build_theme() -> Theme:
	var t := Theme.new()

	if ResourceLoader.exists(PIXEL_FONT_PATH):
		t.default_font = load(PIXEL_FONT_PATH)
		t.default_font_size = 18

	t.set_stylebox("panel", "PanelContainer", _flat_style(COLOR_PANEL, COLOR_ACCENT))

	t.set_stylebox("normal", "Button", _flat_style(COLOR_PANEL, COLOR_ACCENT))
	t.set_stylebox("hover", "Button", _flat_style(COLOR_ACCENT, COLOR_ACCENT_HOVER))
	t.set_stylebox("pressed", "Button", _flat_style(COLOR_ACCENT_HOVER, COLOR_TEXT))
	t.set_stylebox("focus", "Button", _flat_style(COLOR_PANEL, COLOR_TEXT))
	t.set_color("font_color", "Button", COLOR_TEXT)
	t.set_color("font_hover_color", "Button", COLOR_TEXT)
	t.set_color("font_pressed_color", "Button", COLOR_TEXT)

	t.set_color("font_color", "Label", COLOR_TEXT)

	t.set_stylebox("slider", "HSlider", _flat_style(COLOR_PANEL, COLOR_ACCENT))
	t.set_stylebox("grabber_area", "HSlider", _flat_style(COLOR_ACCENT, COLOR_ACCENT))

	return t

func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(CORNER_RADIUS)
	style.set_content_margin_all(12)
	return style
