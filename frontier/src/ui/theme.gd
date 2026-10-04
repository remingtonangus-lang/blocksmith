class_name UITheme
extends RefCounted
## Sable River's 1899 print identity: aged paper, iron-gall ink, oxblood accents; IM Fell for text, Rye for display.

const PAPER := Color(0.90, 0.83, 0.68)
const INK := Color(0.16, 0.11, 0.08)
const INK_SOFT := Color(0.16, 0.11, 0.08, 0.75)
const OXBLOOD := Color(0.48, 0.12, 0.09)
const BRASS := Color(0.78, 0.64, 0.36)
const SLATE := Color(0.42, 0.52, 0.60)
const OCHRE := Color(0.80, 0.60, 0.26)
const SHADOW := Color(0, 0, 0, 0.55)

static var _fonts := {}

static func font(name: String) -> Font:
	if _fonts.has(name):
		return _fonts[name]
	var path: String = {"body": "IMFeENrm28P.ttf", "italic": "IMFeENit28P.ttf", "caps": "IMFeENsc28P.ttf",
		"display": "Rye-Regular.ttf", "poster": "Sancreek-Regular.ttf", "serif": "OldStandard-Regular.ttf",
		"serif_bold": "OldStandard-Bold.ttf"}.get(name, "IMFeENrm28P.ttf")
	var f = load("res://assets/fonts/" + path)
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[name] = f
	return f

static func label(text: String, size: int, font_name := "body", color := Color.WHITE, shadow := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_name))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", SHADOW)
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", 4)
	return l
