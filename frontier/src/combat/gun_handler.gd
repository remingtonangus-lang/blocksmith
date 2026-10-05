class_name GunHandler
extends Node3D
## One actor's firearms: equipped weapon, ammo, cocking/cycling and reload states, firing with spread and simple
## ballistics (gravity drop past 80 m, travel time), hit resolution through Damageable hitboxes, impact effects,
## recoil kick for the player camera, and the Nerve sequence executor. Used by the player and by AI gunmen.

signal fired(weapon_id: String, origin: Vector3, dir: Vector3)
signal reloaded(weapon_id: String)
signal empty(weapon_id: String)
signal hit_landed(info: Dictionary)

const WORLD_MASK := 1
const BODY_MASK := 0                   # bodies are hit only through their zone hitboxes (layer 16)
const HITBOX_MASK := 16
const GRAVITY := 9.81

var owner_actor: Node3D
var damageable: Damageable
var weapons: Array[String] = ["lockhart_sa", "merriman_lever"]
var current := 0
var clip := {}                         # weapon id -> rounds loaded
var ammo := {"revolver": 48, "repeater": 60, "rifle": 20, "shotgun": 24, "varmint": 40}
var drawn := false
var cooldown := 0.0
var reloading := false
var _reload_t := 0.0
var recoil_kick := Vector2.ZERO        # pitch/yaw degrees, read and decayed by the camera owner
var accuracy_bonus := 0.0              # 0..1, from aiming time / skill
var _aim_time := 0.0
var rng := RandomNumberGenerator.new()
var is_player := false
# condition (1 clean .. 0 fouled) and special ammunition (src: QUALITY_BAR 8 "weapon wear/cleaning, ammo types")
const WEAR := {"pistol": 0.0025, "rifle": 0.002, "shotgun": 0.004}
const AMMO_VARIANTS := {"revolver": ["revolver_express"], "repeater": ["repeater_express"],
	"rifle": ["rifle_express", "rifle_split"], "shotgun": ["shotgun_slug"], "varmint": []}
const AMMO_MODS := {
	"revolver_express": {"name": "Express", "damage": 1.18, "range": 1.25, "velocity": 1.2},
	"repeater_express": {"name": "Express", "damage": 1.15, "range": 1.25, "velocity": 1.2},
	"rifle_express": {"name": "Express", "damage": 1.12, "range": 1.2, "velocity": 1.15},
	"rifle_split": {"name": "Split-point", "damage": 1.25, "range": 0.85, "velocity": 0.95, "pelt": -1},
	"shotgun_slug": {"name": "Slug", "pellets": 1, "damage": 6.0, "range": 4.0, "falloff": 2.5, "spread": 0.3},
}
var condition := {}                    # weapon id -> 0..1
var ammo_sel := {}                     # ammo base -> selected variant ("" standard)
var loaded := {}                       # weapon id -> variant the rounds in the clip are ("" standard)
var jams := 0

func setup(actor: Node3D, dmg: Damageable, player := false) -> void:
	owner_actor = actor
	damageable = dmg
	is_player = player
	rng.seed = hash(actor.name) + 17
	for w in weapons:
		clip[w] = Weapons.get_def(w).capacity

func weapon_id() -> String:
	return weapons[current] if current < weapons.size() else ""

func def() -> Dictionary:
	return Weapons.get_def(weapon_id())

func cond(id := "") -> float:
	return float(condition.get(id if id != "" else weapon_id(), 1.0))

func loaded_variant(id := "") -> String:
	return str(loaded.get(id if id != "" else weapon_id(), ""))

## The current weapon's numbers after the loaded ammunition and its condition (a fouled gun throws wider, hits a
## little softer and reloads slower).
func effective_def() -> Dictionary:
	var d := def().duplicate()
	var m: Dictionary = AMMO_MODS.get(loaded_variant(), {})
	if not m.is_empty():
		d.damage = float(d.damage) * float(m.get("damage", 1.0))
		d.range = float(d.range) * float(m.get("range", 1.0))
		d.falloff = float(d.falloff) * float(m.get("falloff", m.get("range", 1.0)))
		d.velocity = float(d.velocity) * float(m.get("velocity", 1.0))
		if m.has("pellets"):
			d.pellets = int(m.pellets)
		if m.has("spread"):
			d.spread = float(d.spread) * float(m.spread)
			d.aim_spread = float(d.aim_spread) * float(m.spread)
		d.pelt_penalty = int(m.get("pelt", 0))
	var c := cond()
	var foul := clampf((0.6 - c) / 0.6, 0.0, 1.0)
	d.spread = float(d.spread) * (1.0 + foul * 0.9)
	d.aim_spread = float(d.aim_spread) * (1.0 + foul * 1.4)
	d.damage = float(d.damage) * (1.0 - foul * 0.12)
	return d

func ammo_name(id := "") -> String:
	var v := loaded_variant(id)
	return str(AMMO_MODS[v].name) if AMMO_MODS.has(v) else ""

## Cycle the ammunition the next reload uses for the current weapon's calibre (standard -> variants owned).
func cycle_ammo() -> String:
	return cycle_ammo_base(str(def().ammo))

func cycle_ammo_base(base: String) -> String:
	var opts: Array = [""]
	for v in AMMO_VARIANTS.get(base, []):
		if int(ammo.get(v, 0)) > 0:
			opts.append(v)
	var i := opts.find(str(ammo_sel.get(base, "")))
	var nxt: String = opts[(i + 1) % opts.size()]
	ammo_sel[base] = nxt
	return nxt

func clean(id := "") -> void:
	condition[id if id != "" else weapon_id()] = 1.0

func clean_all() -> void:
	for w in weapons:
		condition[w] = 1.0

func select(i: int) -> void:
	if i >= 0 and i < weapons.size() and i != current:
		current = i
		reloading = false
		cooldown = 0.45

func _process(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	recoil_kick = recoil_kick.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * dt))
	if reloading:
		_reload_t -= dt
		if _reload_t <= 0.0:
			_reload_step()

func aim_tick(aiming: bool, dt: float) -> void:
	_aim_time = _aim_time + dt if aiming else 0.0
	accuracy_bonus = clampf(_aim_time / 0.8, 0.0, 1.0)

func can_fire() -> bool:
	return weapon_id() != "" and drawn and cooldown <= 0.0 and not reloading and clip.get(weapon_id(), 0) > 0

## Fire toward `target_dir` from `origin`. aimed = steadier. Returns the list of hit infos.
func fire(origin: Vector3, target_dir: Vector3, aimed: bool, spread_scale := 1.0) -> Array:
	var id := weapon_id()
	if id == "" or not drawn or cooldown > 0.0 or reloading:
		return []
	if clip.get(id, 0) <= 0:
		empty.emit(id)
		start_reload()
		return []
	var d := effective_def()
	# a badly fouled gun can jam: the round stays, the action must be cleared (clean the gun to stop it)
	var c := cond(id)
	if c < 0.3 and rng.randf() < (0.3 - c) * 0.35:
		jams += 1
		cooldown = 1.4
		if is_player:
			Game.say("Jammed. That iron needs cleaning.", 2.5)
		if Game.audio != null and Game.audio.has_sound("gun_jam"):
			Game.audio.play("gun_jam", origin)
		Game.log_event("jam", {"weapon": id, "condition": snappedf(c, 0.01)})
		return []
	clip[id] -= 1
	cooldown = d.cock_time
	var wet := 0.0
	if Game.sky != null:
		wet = float(Game.sky.get("wet"))
	condition[id] = maxf(c - float(WEAR.get(d.kind, 0.0025)) * (1.0 + wet * 0.8), 0.0)
	var spread_deg: float = (d.aim_spread if aimed else d.spread) * lerpf(1.0, 0.55, accuracy_bonus) * spread_scale
	var results := []
	for p in int(d.pellets):
		var dir := _spread_dir(target_dir.normalized(), spread_deg)
		var hit := _trace(origin, dir, d)
		if not hit.is_empty():
			results.append(hit)
	recoil_kick += Vector2(d.recoil * rng.randf_range(0.8, 1.2), d.recoil * rng.randf_range(-0.3, 0.3))
	_aim_time *= 0.4
	fired.emit(id, origin, target_dir)
	Game.noise.emit(origin, 260.0 if d.kind != "rifle" else 380.0, owner_actor)
	Game.log_event("shot", {"by": str(owner_actor.name), "weapon": id, "hits": results.size()})
	if Game.audio != null:
		Game.audio.gunshot(d.sound, origin, is_player)
	return results

func _spread_dir(dir: Vector3, deg: float) -> Vector3:
	var r := deg_to_rad(deg) * sqrt(rng.randf()) * 0.5
	var a := rng.randf() * TAU
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	return (dir + (side * cos(a) + up * sin(a)) * tan(r)).normalized()

## Ray march with gravity drop in segments (80 m flat, then curved), hitboxes before world.
func _trace(origin: Vector3, dir: Vector3, d: Dictionary) -> Dictionary:
	var space := owner_actor.get_world_3d().direct_space_state
	var v: float = d.velocity
	var max_d: float = d.falloff * 1.3
	var pos := origin
	var vel := dir * v
	var travelled := 0.0
	var exclude: Array[RID] = []
	if owner_actor is CollisionObject3D:
		exclude.append(owner_actor.get_rid())
	for hb in owner_actor.find_children("*", "Area3D", true, false):
		exclude.append(hb.get_rid())
	var seg_t := 80.0 / v
	while travelled < max_d:
		var step := vel * seg_t
		if travelled + step.length() > max_d:
			step = step.normalized() * (max_d - travelled)
		var q := PhysicsRayQueryParameters3D.create(pos, pos + step, WORLD_MASK | BODY_MASK | HITBOX_MASK)
		q.collide_with_areas = true
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var dist := travelled + pos.distance_to(hit.position)
			var info := {"position": hit.position, "normal": hit.normal, "distance": dist, "direction": step.normalized(),
				"collider": hit.collider, "weapon": weapon_id(), "attacker": owner_actor, "ammo": loaded_variant()}
			var col = hit.collider
			if col != null and col.has_meta("damageable"):
				var target: Damageable = col.get_meta("damageable")
				info["zone"] = col.get_meta("zone", "chest")
				info["amount"] = Weapons.damage_at(d, dist)
				info["impulse"] = step.normalized() * (info.amount * 0.08)
				target.apply_hit(info)
				info["target"] = target
				hit_landed.emit(info)
			Effects.impact(owner_actor.get_tree().current_scene, info)
			return info
		travelled += step.length()
		pos += step
		vel.y -= GRAVITY * seg_t
	return {}

func start_reload() -> void:
	var id := weapon_id()
	if id == "":
		return
	var d := def()
	if reloading or clip.get(id, 0) >= d.capacity or ammo.get(d.ammo, 0) <= 0:
		return
	reloading = true
	_reload_t = float(d.get("reload_all", d.get("reload_each", 0.6))) * _reload_scale()

func _reload_scale() -> float:
	return 1.0 + clampf((0.6 - cond()) / 0.6, 0.0, 1.0) * 0.5

func _reload_step() -> void:
	var id := weapon_id()
	if id == "":                 # disarmed mid-reload
		reloading = false
		return
	var d := def()
	# rounds come from the selected special box while it lasts (the clip is then that kind), else standard
	var pool: String = d.ammo
	var sel := str(ammo_sel.get(d.ammo, ""))
	if sel != "" and int(ammo.get(sel, 0)) > 0:
		pool = sel
	loaded[id] = "" if pool == d.ammo else pool
	var have: int = ammo.get(pool, 0)
	if d.has("reload_all"):
		var n := mini(d.capacity - clip[id], have)
		clip[id] += n
		ammo[pool] = have - n
		reloading = false
	else:
		if have > 0 and clip[id] < d.capacity:
			clip[id] += 1
			ammo[pool] = have - 1
		if clip[id] >= d.capacity or ammo[pool] <= 0:
			reloading = false
		else:
			_reload_t = d.reload_each * _reload_scale()
	if not reloading:
		reloaded.emit(id)

func cancel_reload() -> void:
	reloading = false
