class_name InputGlyphs
extends RefCounted
## Button prompts follow the device in use and any rebinding: "[E]  Talk" reads "[Y]  Talk" on a controller and
## "[K]  Talk" after Interact is rebound to K. Prompt text is written with the default keyboard key in brackets;
## the HUD passes every prompt through sub().

const TOKENS := {"E": "interact", "F": "mount", "T": "antagonize", "N": "defuse", "H": "whistle", "R": "reload",
	"Q": "nerve", "Z": "ride_auto", "G": "holster", "M": "map", "J": "journal", "I": "satchel"}

static func label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var want_pad := Accessibility.last_pad
	for e in InputMap.action_get_events(action):
		if want_pad and e is InputEventJoypadButton:
			return MenusNames.pad(e.button_index)
		if not want_pad and e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			var k := code if Game.headless else DisplayServer.keyboard_get_keycode_from_physical(code)
			return OS.get_keycode_string(k)
	return "?"

static func sub(text: String) -> String:
	if not text.contains("["):
		return text
	for t in TOKENS:
		var tok := "[%s]" % t
		if text.contains(tok):
			text = text.replace(tok, "[%s]" % label(TOKENS[t]))
	return text
