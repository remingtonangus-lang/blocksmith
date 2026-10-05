class_name Accessibility
extends CanvasLayer
## Accessibility layer owned by Menus: colour-vision assist filter over everything (top canvas layer), text/UI
## scale, and the last input device (aim assist defaults to controller-only, like most console shooters).
## Settings live in Menus.settings: colour_mode, colour_strength, text_scale, aim_assist, aim_toggle.

const COLOUR_MODES := ["off", "protan", "deutan", "tritan"]
const COLOUR_LABELS := ["Off", "Protanopia (red-weak)", "Deuteranopia (green-weak)", "Tritanopia (blue-weak)"]

static var last_pad := false          # last look/aim input came from a gamepad
static var aim_assist := "controller"  # off | controller | always
static var aim_toggle := false         # aim latches on press instead of hold

var _rect: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/colour_assist.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.3:
			last_pad = true
	elif event is InputEventJoypadButton:
		last_pad = true
	elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
		last_pad = false

func apply(s: Dictionary) -> void:
	var m := COLOUR_MODES.find(str(s.get("colour_mode", "off")))
	_rect.visible = m > 0 and not Game.is_vr
	_mat.set_shader_parameter("mode", maxi(m, 0))
	_mat.set_shader_parameter("strength", float(s.get("colour_strength", 1.0)))
	aim_assist = str(s.get("aim_assist", "controller"))
	aim_toggle = bool(s.get("aim_toggle", false))
	var win := get_window()
	if win:
		win.content_scale_factor = clampf(float(s.get("text_scale", 1.0)), 0.8, 1.5)

static func assist_on() -> bool:
	return aim_assist == "always" or (aim_assist == "controller" and last_pad)
