class_name Nerve
extends Node
## Nerve — Ruth's slow-time aiming. While aiming, press Nerve: the world slows (time scale 0.28), colour drains
## toward a warm sepia with a vignette and a heartbeat; each press of Fire marks the point under the sights (up to
## the rounds in the cylinder); releasing Aim/Nerve (or filling the marks) fires the marked shots in a fast
## sequence. The meter drains in real time while active and refills slowly (faster on kills/headshots).
## Look: a strong desaturated sepia grade with paper grain and a heartbeat-timed vignette (shaders/nerve_overlay),
## the AudioDirector heartbeat, and a hand-inked X printed on every mark (sticks to the body part it marked).
## Execution cuts the camera between an over-the-shoulder telephoto and a close view of each target as it is shot.
## Ranks (Standing/skill) raise capacity and duration.

signal activated
signal deactivated

const SLOW := 0.28
var meter := 100.0
var max_meter := 100.0
var drain_per_sec := 14.0          # real seconds
var refill_per_sec := 1.2
var active := false
var marks: Array = []              # [{pos, target(Damageable or null), zone}]
var gun: GunHandler
var overlay: ColorRect
var _executing := false
var _exec_t := 0.0
var _cine: Camera3D                # execution camera (cuts per shot)
var _shot_i := 0
static var _ink_tex: ImageTexture

func setup(g: GunHandler, canvas: CanvasLayer) -> void:
	gun = g
	if canvas != null:
		overlay = ColorRect.new()
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/nerve_overlay.gdshader")
		overlay.material = sm
		overlay.visible = false
		canvas.add_child(overlay)

func can_activate() -> bool:
	return not active and meter > 15.0 and gun != null and gun.drawn

func activate() -> void:
	if not can_activate():
		return
	active = true
	marks.clear()
	Engine.time_scale = SLOW
	if overlay:
		overlay.visible = true
	if Game.audio:
		Game.audio.set_nerve(true)
	activated.emit()

func mark(origin: Vector3, dir: Vector3) -> void:
	if not active or _executing:
		return
	var rounds: int = gun.clip.get(gun.weapon_id(), 0)
	if marks.size() >= rounds:
		return
	var space := gun.owner_actor.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 250.0, GunHandler.WORLD_MASK | GunHandler.HITBOX_MASK)
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	var m := {"pos": origin + dir * 250.0, "node": null}
	if not hit.is_empty():
		m.pos = hit.position
		m.node = hit.collider
	m["ink"] = _ink(m)
	marks.append(m)
	if Game.audio:
		Game.audio.ui("nerve_mark")
	if marks.size() >= rounds:
		execute()

func execute() -> void:
	if not active or _executing:
		return
	if marks.is_empty():
		deactivate()
		return
	_executing = true
	_exec_t = 0.0
	_shot_i = 0

func deactivate() -> void:
	active = false
	_executing = false
	for m in marks:
		_free_ink(m)
	marks.clear()
	if _cine != null and is_instance_valid(_cine):
		_cine.queue_free()
		_cine = null
		if Game.camera != null and is_instance_valid(Game.camera):
			Game.camera.make_current()
	Engine.time_scale = 1.0
	if overlay:
		overlay.visible = false
	if Game.audio:
		Game.audio.set_nerve(false)
	deactivated.emit()

func _process(dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	if active:
		meter = maxf(meter - drain_per_sec * real_dt, 0.0)
		if overlay:
			(overlay.material as ShaderMaterial).set_shader_parameter("strength", 1.0)
		if _executing:
			_exec_t -= real_dt
			if _exec_t <= 0.0 and not marks.is_empty():
				var m: Dictionary = marks.pop_front()
				var origin := gun.owner_actor.global_position + Vector3(0, 1.45, 0)
				var tgt: Vector3 = m.pos
				# re-aim at the marked body part if the target moved (marks stick to hitboxes)
				if m.node != null and is_instance_valid(m.node):
					tgt = (m.node as Node3D).global_position
				gun.cooldown = 0.0
				_cut_to(origin, tgt)
				gun.fire(origin, (tgt - origin).normalized(), true, 0.15)
				_free_ink(m)
				_exec_t = 0.11 if Game.headless else 0.3
			elif marks.is_empty() and _exec_t <= 0.0:
				deactivate()
		elif meter <= 0.0:
			execute()
	else:
		meter = minf(meter + refill_per_sec * real_dt, max_meter)

func reward(amount: float) -> void:
	meter = minf(meter + amount, max_meter)

# ------------------------------------------------------------------------------------------------- ink marks
static func _ink_texture() -> ImageTexture:
	if _ink_tex != null:
		return _ink_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1899
	# two brush strokes, thicker in the middle, ragged edges, a blot where they cross
	for stroke in [[Vector2(10, 12), Vector2(54, 52)], [Vector2(52, 10), Vector2(12, 54)]]:
		var a: Vector2 = stroke[0]
		var b: Vector2 = stroke[1]
		for y in n:
			for x in n:
				var p := Vector2(x, y)
				var ab := b - a
				var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var w := 2.2 + 3.2 * sin(t * PI) + rng.randf_range(-0.6, 0.6)
				var al := clampf((w - d) / 1.4, 0.0, 1.0)
				if al > 0.0:
					var c := img.get_pixel(x, y)
					var ink := Color(0.32, 0.04, 0.03, maxf(c.a, al * (0.85 + 0.15 * rng.randf())))
					img.set_pixel(x, y, ink)
	_ink_tex = ImageTexture.create_from_image(img)
	return _ink_tex

func _ink(m: Dictionary) -> Node3D:
	if Game.headless or gun == null:
		return null
	var sp := Sprite3D.new()
	sp.texture = _ink_texture()
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.no_depth_test = true
	sp.fixed_size = true
	sp.pixel_size = 0.0009
	sp.shaded = false
	sp.render_priority = 10
	sp.modulate = Color(1, 1, 1, 0.95)
	sp.add_to_group("nerve_ink")
	var parent: Node = m.node if m.node is Node3D and is_instance_valid(m.node) else gun.owner_actor.get_tree().current_scene
	parent.add_child(sp)
	sp.global_position = m.pos
	return sp

func _free_ink(m: Dictionary) -> void:
	var sp = m.get("ink")
	if sp is Node and is_instance_valid(sp):
		sp.queue_free()
	m["ink"] = null

## Execution camera: alternate a telephoto over Ruth's shoulder and a close view of the target being hit.
func _cut_to(origin: Vector3, tgt: Vector3) -> void:
	if Game.headless or gun == null or not gun.is_player:
		return
	if _cine == null or not is_instance_valid(_cine):
		_cine = Camera3D.new()
		_cine.name = "NerveCam"
		gun.owner_actor.get_tree().current_scene.add_child(_cine)
		if Game.camera != null:
			_cine.attributes = Game.camera.attributes
			_cine.environment = Game.camera.environment
	var to := (tgt - origin)
	to.y = 0.0
	if to.length() < 0.1:
		to = Vector3.FORWARD
	to = to.normalized()
	var right := to.cross(Vector3.UP).normalized()
	if _shot_i % 2 == 0:
		_cine.fov = 24.0
		_cine.global_position = origin + right * 0.55 - to * 0.9 + Vector3.UP * 0.25
	else:
		var side := right * (1.0 if int(_shot_i / 2.0) % 2 == 0 else -1.0)
		_cine.fov = 38.0
		_cine.global_position = tgt - to * 2.4 + side * 1.4 + Vector3.UP * 0.35
	_cine.look_at(tgt, Vector3.UP)
	_cine.make_current()
	_shot_i += 1
