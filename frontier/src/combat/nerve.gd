class_name Nerve
extends Node
## Nerve — Ruth's slow-time aiming. While aiming, press Nerve: the world slows (time scale 0.28), colour drains
## toward a warm sepia with a vignette and a heartbeat; each press of Fire marks the point under the sights (up to
## the rounds in the cylinder); releasing Aim/Nerve (or filling the marks) fires the marked shots in a fast
## sequence. The meter drains in real time while active and refills slowly (faster on kills/headshots).
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

func deactivate() -> void:
	active = false
	_executing = false
	marks.clear()
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
				gun.fire(origin, (tgt - origin).normalized(), true, 0.15)
				_exec_t = 0.11
			elif marks.is_empty() and _exec_t <= 0.0:
				deactivate()
		elif meter <= 0.0:
			execute()
	else:
		meter = minf(meter + refill_per_sec * real_dt, max_meter)

func reward(amount: float) -> void:
	meter = minf(meter + amount, max_meter)
