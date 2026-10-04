extends CanvasLayer
## In-game HUD: a paper map inset (bottom left, rotates with the camera, roads/rivers/towns from the generated
## map), three engraved gauges (health, stamina, Nerve; horse gauges when mounted), ammunition, crosshair with hit
## confirmation, context prompts, subtitles and notices. Scales with the window height; hidden in cinematics.

var map_tex: Texture2D
var player: Node
var root: Control
var map_panel: Control
var map_rect: TextureRect
var map_mat: ShaderMaterial
var gauges: Control
var ammo_label: Label
var weapon_label: Label
var prompt_label: Label
var subtitle_label: Label
var notice_label: Label
var location_label: Label
var crosshair: Control
var _notice_t := 0.0
var _sub_t := 0.0
var _loc_t := 0.0
var _hit_t := 0.0
var _last_place := ""
var cinematic := false

func setup(p: Node) -> void:
	player = p
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	map_tex = load("res://data/world/map.png") if ResourceLoader.exists("res://data/world/map.png") else null
	_build_map()
	_build_gauges()
	ammo_label = UITheme.label("", 30, "serif_bold", UITheme.PAPER)
	weapon_label = UITheme.label("", 22, "italic", UITheme.PAPER)
	prompt_label = UITheme.label("", 26, "body", UITheme.PAPER)
	subtitle_label = UITheme.label("", 30, "body", Color(1, 0.97, 0.9))
	notice_label = UITheme.label("", 30, "caps", UITheme.PAPER)
	location_label = UITheme.label("", 54, "display", UITheme.PAPER)
	for l in [ammo_label, weapon_label, prompt_label, subtitle_label, notice_label, location_label]:
		root.add_child(l)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)
	Game.message.connect(notice)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_map() -> void:
	map_panel = Control.new()
	map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map_panel)
	map_rect = TextureRect.new()
	map_rect.texture = map_tex
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_mat = ShaderMaterial.new()
	map_mat.shader = load("res://shaders/ui_map_inset.gdshader")
	map_rect.material = map_mat
	map_panel.add_child(map_rect)
	map_panel.draw.connect(_draw_map_overlay)

func _build_gauges() -> void:
	gauges = Control.new()
	gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauges.draw.connect(_draw_gauges)
	root.add_child(gauges)

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var u := vs.y / 1080.0
	var m := 34.0 * u
	var ms := 250.0 * u
	map_panel.position = Vector2(m, vs.y - m - ms)
	map_panel.size = Vector2(ms, ms)
	map_rect.position = Vector2.ZERO
	map_rect.size = Vector2(ms, ms)
	gauges.position = Vector2(m + ms + 14 * u, vs.y - m - ms)
	gauges.size = Vector2(60 * u, ms)
	ammo_label.position = Vector2(vs.x - 260 * u, vs.y - 110 * u)
	ammo_label.size = Vector2(230 * u, 40 * u)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.position = Vector2(vs.x - 460 * u, vs.y - 70 * u)
	weapon_label.size = Vector2(430 * u, 30 * u)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt_label.position = Vector2(vs.x * 0.5 - 300 * u, vs.y - 200 * u)
	prompt_label.size = Vector2(600 * u, 40 * u)
	subtitle_label.position = Vector2(vs.x * 0.5 - 600 * u, vs.y - 150 * u)
	subtitle_label.size = Vector2(1200 * u, 90 * u)
	notice_label.position = Vector2(vs.x * 0.5 - 500 * u, 90 * u)
	notice_label.size = Vector2(1000 * u, 50 * u)
	location_label.position = Vector2(vs.x * 0.5 - 600 * u, vs.y * 0.18)
	location_label.size = Vector2(1200 * u, 80 * u)
	crosshair.position = vs * 0.5
	for l in [ammo_label, weapon_label, prompt_label, subtitle_label, notice_label, location_label]:
		var fs: int = l.get_theme_font_size("font_size")
		l.set_meta("base_size", l.get_meta("base_size", fs))
		l.add_theme_font_size_override("font_size", int(l.get_meta("base_size") * u))

func _process(dt: float) -> void:
	if player == null or Game.world == null:
		return
	root.visible = not cinematic
	var w: WorldData = Game.world
	var p: Vector3 = player.global_position
	var yaw: float = player.cam_yaw if "cam_yaw" in player else 0.0
	map_mat.set_shader_parameter("center", Vector2((p.x + w.size_m * 0.5) / w.size_m, (p.z + w.size_m * 0.5) / w.size_m))
	map_mat.set_shader_parameter("rotation", yaw)
	map_mat.set_shader_parameter("zoom", 0.045 if player.get("on_horse") == null else 0.07)
	map_panel.queue_redraw()
	gauges.queue_redraw()
	crosshair.queue_redraw()
	var gun = player.get("gun")
	if gun != null and gun.drawn:
		var d: Dictionary = gun.def()
		ammo_label.text = "%d  |  %d" % [gun.clip.get(gun.weapon_id(), 0), gun.ammo.get(d.ammo, 0)]
		weapon_label.text = d.name + ("  — reloading" if gun.reloading else "")
	else:
		ammo_label.text = ""
		weapon_label.text = ""
	_notice_t -= dt
	if _notice_t <= 0.0:
		notice_label.text = ""
	_sub_t -= dt
	if _sub_t <= 0.0:
		subtitle_label.text = ""
	_hit_t -= dt
	# arriving somewhere named: show the place title once
	_loc_t -= dt
	var near := w.nearest_settlement(p.x, p.z)
	if not near.is_empty():
		var inside := Vector2(near.x - p.x, near.z - p.z).length() < float(near.r) + 40.0
		if inside and near.name != _last_place:
			_last_place = near.name
			location_label.text = near.name
			_loc_t = 5.0
		elif not inside and Vector2(near.x - p.x, near.z - p.z).length() > float(near.r) + 200.0 and _last_place == near.name:
			_last_place = ""
	location_label.modulate.a = clampf(_loc_t, 0.0, 1.0)

func prompt(text: String) -> void:
	prompt_label.text = text

func subtitle(speaker: String, text: String, seconds := 4.0) -> void:
	subtitle_label.text = ("%s:  %s" % [speaker, text]) if speaker != "" else text
	_sub_t = seconds

func notice(text: String, seconds := 4.0) -> void:
	notice_label.text = text
	_notice_t = seconds

func hit_confirm(kill: bool) -> void:
	_hit_t = 0.35 if not kill else 0.7

func _draw_map_overlay() -> void:
	var s := map_panel.size
	var c := s * 0.5
	# frame: ink border with a brass inner rule
	map_panel.draw_rect(Rect2(Vector2.ZERO, s), UITheme.INK, false, 4.0)
	map_panel.draw_rect(Rect2(Vector2(5, 5), s - Vector2(10, 10)), UITheme.BRASS, false, 1.5)
	# player marker: a small arrowhead pointing where the body faces relative to the camera
	var face: float = player.get("facing") if player.get("facing") != null else 0.0
	var yaw: float = player.cam_yaw if "cam_yaw" in player else 0.0
	var a := -(face - yaw)
	var tip := c + Vector2(sin(a), -cos(a)) * 11.0
	var l := c + Vector2(sin(a + 2.5), -cos(a + 2.5)) * 8.0
	var r := c + Vector2(sin(a - 2.5), -cos(a - 2.5)) * 8.0
	map_panel.draw_colored_polygon(PackedVector2Array([tip, l, c, r]), UITheme.OXBLOOD)
	map_panel.draw_polyline(PackedVector2Array([tip, l, c, r, tip]), UITheme.INK, 1.5)
	# north tick
	var yaw2: float = player.cam_yaw if "cam_yaw" in player else 0.0
	var npos := c + Vector2(sin(yaw2), -cos(yaw2)) * (s.x * 0.5 - 14.0)
	map_panel.draw_string(UITheme.font("caps"), npos + Vector2(-6, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s.y / 250.0), UITheme.INK)

func _draw_gauges() -> void:
	var s := gauges.size
	var vals := [
		[float(player.get("health")) / 100.0 if player.get("health") != null else 1.0, UITheme.OXBLOOD],
		[float(player.get("stamina")) / 100.0 if player.get("stamina") != null else 1.0, UITheme.OCHRE],
		[(player.nerve.meter / player.nerve.max_meter) if player.get("nerve") != null else 1.0, UITheme.SLATE],
	]
	var horse = player.get("on_horse")
	if horse != null and horse.get("stamina") != null:
		vals.append([float(horse.stamina) / 100.0, UITheme.BRASS])
	var bw := s.x / 4.6
	for i in vals.size():
		var x := i * bw * 1.15
		var rect := Rect2(Vector2(x, 0), Vector2(bw, s.y))
		gauges.draw_rect(rect, Color(0, 0, 0, 0.35))
		var v: float = clampf(vals[i][0], 0.0, 1.0)
		var fill := Rect2(Vector2(x + 3, 3 + (s.y - 6) * (1.0 - v)), Vector2(bw - 6, (s.y - 6) * v))
		gauges.draw_rect(fill, vals[i][1])
		gauges.draw_rect(rect, UITheme.INK, false, 2.0)
		for k in range(1, 4):
			var y := s.y * k / 4.0
			gauges.draw_line(Vector2(x, y), Vector2(x + bw * 0.35, y), UITheme.INK, 1.0)

func _draw_crosshair() -> void:
	var aiming: bool = player.get("intent") != null and player.intent.get("aim", false)
	if not aiming:
		return
	var col := Color(1, 1, 1, 0.85)
	crosshair.draw_circle(Vector2.ZERO, 2.2, col)
	if _hit_t > 0.0:
		var k := 9.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			crosshair.draw_line(d * 5.0, d * k, Color(1, 0.9, 0.85, clampf(_hit_t * 3.0, 0.0, 1.0)), 2.0)
