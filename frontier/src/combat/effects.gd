class_name Effects
extends RefCounted
## Short-lived combat effects: bullet impacts (dust/splinters/sparks/blood by surface), muzzle flashes, tracers.
## CPUParticles3D so the same code runs on the Mobile renderer (Quest). Everything frees itself.

static var _dust_mat: StandardMaterial3D
static var _blood_mat: StandardMaterial3D
static var _flash_mat: StandardMaterial3D
static var _hole_tex: ImageTexture

static func _mats() -> void:
	if _dust_mat != null:
		return
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.vertex_color_use_as_albedo = true
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_blood_mat = _dust_mat.duplicate()
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1.0, 0.75, 0.4, 0.9)
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

static func impact(root: Node, info: Dictionary) -> void:
	if root == null or Game.headless:
		return
	_mats()
	var is_body: bool = info.has("target")
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 14 if is_body else 22
	p.lifetime = 0.5 if is_body else 1.4
	p.explosiveness = 0.95
	p.direction = info.get("normal", Vector3.UP)
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5 if is_body else 3.0
	p.gravity = Vector3(0, -6.0 if is_body else -1.2, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.04 if is_body else 0.08
	p.scale_amount_max = 0.09 if is_body else 0.28
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _blood_mat if is_body else _dust_mat
	p.mesh = q
	var grad := Gradient.new()
	if is_body:
		grad.set_color(0, Color(0.35, 0.02, 0.02, 0.95))
		grad.set_color(1, Color(0.25, 0.0, 0.0, 0.0))
	else:
		var gy: float = info.position.y
		var c := Game.world.ctrl(info.position.x, info.position.z) if Game.world else Color(0.5, 0.5, 0.5)
		var dust := Color(0.62, 0.52, 0.40).lerp(Color(0.72, 0.48, 0.33), 1.0 - c.b) if gy > 0.0 else Color(0.6, 0.6, 0.6)
		grad.set_color(0, Color(dust.r, dust.g, dust.b, 0.75))
		grad.set_color(1, Color(dust.r, dust.g, dust.b, 0.0))
	p.color_ramp = grad
	root.add_child(p)
	p.global_position = info.position
	p.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)
	if not is_body:
		var dec := Decal.new()
		dec.size = Vector3(0.12, 0.2, 0.12)
		if _hole_tex == null:
			var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
			for y in 16:
				for x in 16:
					var r := Vector2(x - 7.5, y - 7.5).length() / 7.5
					img.set_pixel(x, y, Color(0.08, 0.06, 0.05, clampf(1.0 - r, 0.0, 1.0) * 0.85))
			_hole_tex = ImageTexture.create_from_image(img)
		dec.texture_albedo = _hole_tex
		root.add_child(dec)
		dec.global_position = info.position
		var n: Vector3 = info.get("normal", Vector3.UP)
		if absf(n.dot(Vector3.UP)) < 0.99:
			dec.look_at(info.position + n.cross(Vector3.UP), n)
		dec.get_tree().create_timer(30.0).timeout.connect(dec.queue_free)

static func muzzle_flash(root: Node, pos: Vector3, dir: Vector3) -> void:
	if root == null or Game.headless:
		return
	_mats()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.4)
	l.light_energy = 6.0
	l.omni_range = 7.0
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos + dir * 0.3
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = _flash_mat
	m.mesh = q
	root.add_child(m)
	m.global_position = pos + dir * 0.25
	var t := l.get_tree().create_timer(0.05)
	t.timeout.connect(func():
		l.queue_free()
		m.queue_free())
