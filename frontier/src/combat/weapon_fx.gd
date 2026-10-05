class_name WeaponFX
extends RefCounted
## Firearm by-products: ejected cases (a small recycled pool of RigidBody3D brass that bounces on the world and
## settles) and black-powder smoke puffs at the muzzle (CPUParticles3D, Mobile-renderer safe). Static helpers.

const POOL_MAX := 24
const LIFE := 9.0
## kind -> [radius, length, colour, metallic]
const CASES := {
	"pistol": [0.0058, 0.033, Color(0.78, 0.58, 0.3), 1.0],
	"rifle": [0.0062, 0.058, Color(0.78, 0.58, 0.3), 1.0],
	"rimfire": [0.0029, 0.015, Color(0.8, 0.62, 0.34), 1.0],
	"shotgun": [0.0105, 0.064, Color(0.55, 0.08, 0.06), 0.0],
}

static var _pool: Array = []             # [body, born_msec]
static var _meshes := {}
static var _smoke_mat: StandardMaterial3D
static var _rng := RandomNumberGenerator.new()

static func _case_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var c: Array = CASES.get(kind, CASES["pistol"])
	var cm := CylinderMesh.new()
	cm.top_radius = c[0] * 0.93
	cm.bottom_radius = c[0]
	cm.height = c[1]
	cm.radial_segments = 10
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = c[2]
	m.metallic = c[3]
	m.roughness = 0.32 if c[3] > 0.5 else 0.6
	cm.material = m
	_meshes[kind] = cm
	return cm

## Throw a spent case from `xform` (the weapon's shell_eject marker: -Z = eject direction).
static func casing(root: Node, kind: String, xform: Transform3D, inherit := Vector3.ZERO) -> void:
	if root == null or Game.headless:
		return
	var body: RigidBody3D = null
	var now := Time.get_ticks_msec()
	# reuse an expired body, else the oldest once the pool is full
	for e in _pool:
		if not is_instance_valid(e[0]):
			continue
		if now - int(e[1]) > LIFE * 1000.0:
			body = e[0]
			e[1] = now
			break
	_pool = _pool.filter(func(e): return is_instance_valid(e[0]))
	if body == null and _pool.size() >= POOL_MAX:
		_pool.sort_custom(func(a, b): return a[1] < b[1])
		body = _pool[0][0]
		_pool[0][1] = now
	if body == null:
		body = RigidBody3D.new()
		body.collision_layer = 0
		body.collision_mask = 1
		body.mass = 0.012
		body.continuous_cd = true
		body.can_sleep = true
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.35
		pm.friction = 0.7
		body.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		var c: Array = CASES.get(kind, CASES["pistol"])
		sh.radius = c[0]
		sh.height = c[1]
		cs.shape = sh
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = _case_mesh(kind)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		root.add_child(body)
		_pool.append([body, now])
	else:
		var mi2: MeshInstance3D = body.get_node("Mesh")
		mi2.mesh = _case_mesh(kind)
		var cs2: CollisionShape3D = body.get_child(0)
		var c2: Array = CASES.get(kind, CASES["pistol"])
		(cs2.shape as CylinderShape3D).radius = c2[0]
		(cs2.shape as CylinderShape3D).height = c2[1]
		if body.get_parent() != root:
			body.get_parent().remove_child(body)
			root.add_child(body)
	body.visible = true
	body.freeze = false
	body.sleeping = false
	var ej := -xform.basis.z.normalized()
	# the case lies across the eject direction (it leaves the action sideways/up)
	var axis := ej.cross(Vector3.UP)
	if axis.length() < 0.1:
		axis = Vector3.RIGHT
	body.global_transform = Transform3D(Basis.looking_at(axis.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2), xform.origin)
	var speed := _rng.randf_range(2.2, 3.4) if kind != "shotgun" else _rng.randf_range(1.2, 2.0)
	body.linear_velocity = inherit + ej * speed + Vector3.UP * _rng.randf_range(0.6, 1.4)
	body.angular_velocity = Vector3(_rng.randf_range(-25, 25), _rng.randf_range(-8, 8), _rng.randf_range(-25, 25))

static func _smoke_material() -> StandardMaterial3D:
	if _smoke_mat != null:
		return _smoke_mat
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, exp(-r * r * 4.0) * clampf((1.0 - r) * 4.0, 0.0, 1.0)))
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_texture = ImageTexture.create_from_image(img)
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.albedo_color = Color(0.8, 0.79, 0.76, 0.26)   # constant tint (per-particle vertex colours render black on some drivers)
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # lit billboards go dark against the sun
	_smoke_mat.disable_receive_shadows = true
	return _smoke_mat

## A puff of powder smoke from the muzzle drifting forward and up; `amount` scales it (shotguns/rifles more).
static func smoke(root: Node, pos: Vector3, dir: Vector3, amount := 1.0) -> void:
	if root == null or Game.headless:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = int(16 * amount) + 6
	p.lifetime = 2.4
	p.explosiveness = 0.85
	p.local_coords = false
	p.direction = dir
	p.spread = 24.0
	p.initial_velocity_min = 1.0 * amount
	p.initial_velocity_max = 3.2 * amount
	p.damping_min = 2.0
	p.damping_max = 3.5
	p.gravity = Vector3(0.15, 0.22, 0.0)
	p.scale_amount_min = 0.24
	p.scale_amount_max = 0.48 * (0.7 + 0.3 * amount)
	p.preprocess = 0.04                          # first rendered frame already simulated
	var sc := Curve.new()
	sc.max_value = 2.0
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = sc
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.material = _smoke_material()
	p.mesh = q
	var grad := Gradient.new()
	grad.set_color(0, Color(0.78, 0.77, 0.74, 0.30))
	grad.set_color(1, Color(0.72, 0.72, 0.70, 0.0))
	p.color_ramp = grad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos + dir * 0.05
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.4).timeout.connect(p.queue_free)
