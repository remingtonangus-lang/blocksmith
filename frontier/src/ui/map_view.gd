extends Control
## Full-screen paper map: pan (drag / left stick), zoom (wheel / triggers), player arrow, mission markers,
## settlements, current waypoint; click / A sets a waypoint.

var menus: Node
var tex: Texture2D
var zoom := 1.0
var center := Vector2(0.5, 0.5)       # map uv at the view centre
var _drag := false

func _ready() -> void:
	tex = load("res://data/world/map.png") if ResourceLoader.exists("res://data/world/map.png") else null
	if Game.player and Game.world:
		var p: Vector3 = Game.player.global_position
		center = Vector2((p.x + Game.world.size_m * 0.5) / Game.world.size_m, (p.z + Game.world.size_m * 0.5) / Game.world.size_m)
		zoom = 2.2

func _uv_to_screen(uv: Vector2) -> Vector2:
	var side := minf(size.x, size.y) * zoom
	return size * 0.5 + (uv - center) * side

func _screen_to_uv(p: Vector2) -> Vector2:
	var side := minf(size.x, size.y) * zoom
	return center + (p - size * 0.5) / side

func _world_to_uv(w: Vector3) -> Vector2:
	var s: float = Game.world.size_m
	return Vector2((w.x + s * 0.5) / s, (w.z + s * 0.5) / s)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom = minf(zoom * 1.15, 12.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom = maxf(zoom / 1.15, 0.9)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed and e.double_click:
				_set_wp(e.position)
			_drag = e.pressed
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			_set_wp(e.position)
		queue_redraw()
	elif e is InputEventMouseMotion and _drag:
		center -= e.relative / (minf(size.x, size.y) * zoom)
		queue_redraw()
	elif e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_A:
		_set_wp(size * 0.5)

func _set_wp(screen: Vector2) -> void:
	var uv := _screen_to_uv(screen)
	var s: float = Game.world.size_m
	var w := Vector3(uv.x * s - s * 0.5, 0, uv.y * s - s * 0.5)
	w.y = Game.world.height(w.x, w.z)
	if menus:
		menus.set_waypoint(w)
	queue_redraw()

func _process(dt: float) -> void:
	var pan := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if pan.length() > 0.1:
		center += pan * dt * 0.4 / zoom
		queue_redraw()
	var zi := Input.get_action_strength("fire") - Input.get_action_strength("aim")
	if absf(zi) > 0.1:
		zoom = clampf(zoom * (1.0 + zi * dt * 1.5), 0.9, 12.0)
		queue_redraw()
	center = center.clamp(Vector2.ZERO, Vector2.ONE)

func _draw() -> void:
	if tex:
		var a := _uv_to_screen(Vector2.ZERO)
		var b := _uv_to_screen(Vector2.ONE)
		draw_texture_rect(tex, Rect2(a, b - a), false)
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.INK, false, 4.0)
	if Game.world == null:
		return
	# mission start / objective markers
	var md = Game.get("missions")
	if md != null and md.active == null:
		for m in md.available():
			if m.start_pos != Vector3.ZERO:
				draw_circle(_uv_to_screen(_world_to_uv(m.start_pos)), 9.0, UITheme.OXBLOOD)
	# places with a story, once found (a hollow mark until read and searched)
	if Game.has_meta("landmarks"):
		for mk in Game.get_meta("landmarks").map_marks():
			var sp := _uv_to_screen(_world_to_uv(mk.pos))
			var dia := PackedVector2Array([sp + Vector2(0, -9), sp + Vector2(9, 0), sp + Vector2(0, 9), sp + Vector2(-9, 0), sp + Vector2(0, -9)])
			if mk.done:
				draw_colored_polygon(dia, UITheme.INK)
			draw_polyline(dia, UITheme.INK, 2.5)
			if zoom > 1.8:
				draw_string(UITheme.font("italic"), sp + Vector2(12, 6), str(mk.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.INK)
	# route
	if menus and menus.route.size() > 1:
		var rp := PackedVector2Array()
		for wpt in menus.route:
			rp.append(_uv_to_screen(_world_to_uv(wpt)))
		draw_polyline(rp, UITheme.OXBLOOD, 3.0, true)
	# waypoint
	if menus and menus.waypoint != Vector3.INF:
		var wp := _uv_to_screen(_world_to_uv(menus.waypoint))
		draw_line(wp + Vector2(-10, -10), wp + Vector2(10, 10), UITheme.OXBLOOD, 4.0)
		draw_line(wp + Vector2(-10, 10), wp + Vector2(10, -10), UITheme.OXBLOOD, 4.0)
	# player arrow
	if Game.player:
		var pp := _uv_to_screen(_world_to_uv(Game.player.global_position))
		var f: float = Game.player.facing
		var dir := Vector2(-sin(f), -cos(f))
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([pp + dir * 16.0, pp - dir * 9.0 + side * 9.0, pp - dir * 4.0, pp - dir * 9.0 - side * 9.0])
		draw_colored_polygon(pts, UITheme.OXBLOOD)
		draw_polyline(pts + PackedVector2Array([pts[0]]), UITheme.INK, 2.0)
