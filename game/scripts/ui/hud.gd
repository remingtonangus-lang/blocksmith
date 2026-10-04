class_name Hud
extends CanvasLayer
## The HUD in the Capital's style (thin white lines, grey panels): crosshair with hit marker, health, weapon and
## ammo, interaction prompt, damage direction arcs, a compass strip with site markers, vehicle readouts (speed,
## altitude, heading, weapon heat), capture-point status and a message feed.

var root: Control
var prompt: Label
var health_bar: ColorRect
var health_bg: ColorRect
var weapon_label: Label
var vehicle_label: Label
var msg_box: VBoxContainer
var compass: Control
var cross: Control
var damage_dirs: Array = []      # [angle, time]
var hit_t := 0.0
var _msgs: Array = []
var font_size := 15
var white := Color(0.95, 0.96, 0.97)
var dim := Color(0.95, 0.96, 0.97, 0.55)


func _ready() -> void:
	layer = 20
	G.hud = self
	visible = not (Settings.has_arg("shots") or Settings.has_arg("benchmark")) or Settings.has_arg("hud")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	cross = Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross)
	root.add_child(cross)
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_FULL_RECT)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)
	prompt = _label(Vector2(0, 0), 17)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_bg = ColorRect.new()
	health_bg.color = Color(0.1, 0.11, 0.12, 0.45)
	root.add_child(health_bg)
	health_bar = ColorRect.new()
	health_bar.color = Color(0.92, 0.94, 0.96, 0.9)
	root.add_child(health_bar)
	weapon_label = _label(Vector2(0, 0), 16)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vehicle_label = _label(Vector2(0, 0), 15)
	msg_box = VBoxContainer.new()
	msg_box.position = Vector2(24, 120)
	root.add_child(msg_box)


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", white)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	root.add_child(l)
	return l


func message(text: String, secs: float = 5.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", white)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	msg_box.add_child(l)
	_msgs.append([l, secs])


func damage(amount: float, from: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to := from - cam.global_position
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	var ang := atan2(to.dot(right), to.dot(fwd))
	damage_dirs.append([ang, 1.2])


func hit_marker() -> void:
	hit_t = 0.25


func _process(delta: float) -> void:
	var size := root.get_viewport_rect().size
	var p: Player = G.player
	prompt.text = ""
	if p and is_instance_valid(p):
		var hp := p.health / 100.0
		health_bg.position = Vector2(size.x * 0.5 - 150, size.y - 42)
		health_bg.size = Vector2(300, 6)
		health_bar.position = health_bg.position
		health_bar.size = Vector2(300 * hp, 6)
		health_bar.color = Color(0.92, 0.94, 0.96, 0.9).lerp(Color(0.9, 0.25, 0.2, 0.95), clampf(1.0 - hp * 1.6, 0.0, 1.0))
		var it: Dictionary = p.focus_interactable if "focus_interactable" in p else {}
		if not it.is_empty():
			var key := "X" if Controls.has_pad() else "E"
			prompt.text = "%s   %s" % [key, it["prompt"]]
		var w := ""
		if p.vehicle and p.vehicle.has_method("hud_text"):
			w = p.vehicle.hud_text()
		elif p.weapons and p.weapons.has_method("hud_text"):
			w = p.weapons.hud_text()
		weapon_label.text = w
	prompt.position = Vector2(size.x * 0.5 - 300, size.y * 0.62)
	prompt.size = Vector2(600, 30)
	weapon_label.position = Vector2(size.x - 420, size.y - 70)
	weapon_label.size = Vector2(390, 60)
	vehicle_label.position = Vector2(30, size.y - 90)
	vehicle_label.text = _objectives()
	for m in _msgs:
		m[1] -= delta
		if m[1] < 1.0:
			(m[0] as Label).modulate.a = maxf(m[1], 0.0)
	var keep := []
	for m in _msgs:
		if m[1] > 0.0:
			keep.append(m)
		else:
			(m[0] as Label).queue_free()
	_msgs = keep
	for d in damage_dirs:
		d[1] -= delta
	damage_dirs = damage_dirs.filter(func(d): return d[1] > 0.0)
	hit_t = maxf(0.0, hit_t - delta)
	cross.queue_redraw()
	compass.queue_redraw()


func _objectives() -> String:
	if G.battle == null or not G.battle.started:
		return ""
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(G.battle.front) > 2500.0:
		return ""
	var names := ["A", "B", "C"]
	var s := "FRONT  "
	for k in G.battle.points.size():
		var pt: Dictionary = G.battle.points[k]
		var own: int = pt["owner"]
		s += "%s %s   " % [names[k], ["CAPITAL", "CINDER"][own] if own >= 0 else "CONTESTED"]
	return s


func _draw_cross() -> void:
	var size := root.get_viewport_rect().size
	var c := size * 0.5
	var p: Player = G.player
	if p == null or not is_instance_valid(p):
		return
	var spread := 9.0
	if p.weapons and "spread_px" in p.weapons:
		spread = p.weapons.spread_px
	if p.vehicle == null:
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			cross.draw_line(c + d * spread, c + d * (spread + 8.0), white, 1.5, true)
		cross.draw_circle(c, 1.4, white)
	else:
		cross.draw_arc(c, 14.0, 0.0, TAU, 32, dim, 1.2, true)
		cross.draw_circle(c, 1.6, white)
	if hit_t > 0.0:
		var a := hit_t / 0.25
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			cross.draw_line(c + d * 6.0, c + d * 13.0, Color(1, 1, 1, a), 2.0, true)
	for dd in damage_dirs:
		var ang: float = dd[0]
		var a: float = clampf(dd[1], 0.0, 1.0)
		cross.draw_arc(c, 90.0, ang - PI * 0.5 - 0.25, ang - PI * 0.5 + 0.25, 12, Color(0.95, 0.3, 0.25, a * 0.85), 5.0, true)


func _draw_compass() -> void:
	var size := root.get_viewport_rect().size
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	var heading := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	var cx := size.x * 0.5
	var y := 30.0
	var width := 520.0
	compass.draw_line(Vector2(cx - width * 0.5, y + 12), Vector2(cx + width * 0.5, y + 12), dim, 1.0)
	var font := ThemeDB.fallback_font
	for deg in range(0, 360, 15):
		var d := angle_difference(deg_to_rad(heading), deg_to_rad(deg))
		var x := cx + d / deg_to_rad(90.0) * width * 0.5
		if absf(x - cx) > width * 0.5:
			continue
		var major := deg % 45 == 0
		compass.draw_line(Vector2(x, y + 12), Vector2(x, y + (2 if major else 7)), white if major else dim, 1.2)
		if major:
			var lbl: String = {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}[deg]
			compass.draw_string(font, Vector2(x - 8, y - 4), lbl, HORIZONTAL_ALIGNMENT_CENTER, 16, 13, white)
	# Site markers.
	if G.gen:
		for nm in ["capital", "citadel", "fort_lumen", "front", "radar", "airfield", "harbor"]:
			var sp: Vector3 = G.gen.sites[nm]
			var to := sp - cam.global_position
			var dist := Vector2(to.x, to.z).length()
			var bearing := fposmod(rad_to_deg(atan2(to.x, -to.z)), 360.0)
			var d := angle_difference(deg_to_rad(heading), deg_to_rad(bearing))
			var x := cx + d / deg_to_rad(90.0) * width * 0.5
			if absf(x - cx) > width * 0.5 or dist < 150.0:
				continue
			var label: String = {"capital": "CANDOR", "citadel": "CITADEL", "fort_lumen": "FORT LUMEN", "front": "FRONT",
				"radar": "RADAR", "airfield": "AIRFIELD", "harbor": "HARBOUR"}[nm]
			var col := Color(0.95, 0.4, 0.3) if nm == "front" else Color(0.75, 0.85, 1.0)
			compass.draw_rect(Rect2(x - 3, y + 16, 6, 6), col)
			compass.draw_string(font, Vector2(x - 60, y + 36), "%s %.1f km" % [label, dist / 1000.0], HORIZONTAL_ALIGNMENT_CENTER, 120, 11, col)
