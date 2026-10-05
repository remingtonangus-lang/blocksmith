class_name Melee
extends RefCounted
## Fistfights (Melee: F / B; hold Aim with no gun drawn to block). Strikes find the nearest person in a short cone
## in front, blocks soak most of a blow from the front and leave the attacker open, clean hits stagger, and a fist
## blow that would kill knocks the target down instead (Damageable.knocked_out) to get up again later.
## Animation: a punch clip when the character library has one ("punch_jab", "punch_cross", "punch_body", "block"),
## otherwise a procedural strike (MeleeArm: the fist driven to the target with two-bone arm IK).

const REACH := 1.65
const CONE := deg_to_rad(55.0)
const BLOWS := {
	"jab": {"dmg": 9.0, "zone": "head", "time": 0.38, "side": -1},
	"cross": {"dmg": 15.0, "zone": "head", "time": 0.55, "side": 1},
	"body": {"dmg": 11.0, "zone": "chest", "time": 0.48, "side": 1},
	"stab": {"dmg": 55.0, "zone": "chest", "time": 0.5, "side": 1, "lethal": true},     # the knife
}

static func _forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

static func _alive(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var d = n.get("damageable")
	return d != null and d.alive and not n.get_meta("knocked_down", false)

## Nearest standing person within reach in front of `attacker` (facing yaw), or null.
static func target_for(attacker: Node3D, yaw: float) -> Node3D:
	var fwd := _forward(yaw)
	var best: Node3D = null
	var bd := REACH
	var pool: Array = attacker.get_tree().get_nodes_in_group("humans")
	if Game.player != null:
		pool.append(Game.player)
	for n in pool:
		if n == attacker or not _alive(n):
			continue
		var d: Vector3 = (n as Node3D).global_position - attacker.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < bd and dist > 0.05 and fwd.angle_to(d / dist) < CONE:
			bd = dist
			best = n
	return best

static func is_blocking_against(target: Node3D, attacker: Node3D) -> bool:
	if not target.get_meta("blocking", false):
		return false
	var yaw: float = target.get("facing") if target.get("facing") != null else target.rotation.y
	var to_att := attacker.global_position - target.global_position
	to_att.y = 0.0
	return _forward(yaw).dot(to_att.normalized()) > 0.3

## Throw a blow. Returns {hit, blocked, target, amount, ko}.
static func strike(attacker: Node3D, yaw: float, kind := "jab") -> Dictionary:
	var blow: Dictionary = BLOWS.get(kind, BLOWS.jab)
	var t := target_for(attacker, yaw)
	_animate(attacker, kind, t)
	attacker.set_meta("melee_t", float(blow.time))
	if t == null:
		_sound("punch_whiff", attacker.global_position + Vector3(0, 1.4, 0))
		return {"hit": false}
	var blocked := is_blocking_against(t, attacker)
	var amount: float = blow.dmg * (0.15 if blocked else 1.0)
	var dir := (t.global_position - attacker.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var ko := [false]
	var dmg = t.get("damageable")
	var on_ko := func(_i): ko[0] = true
	dmg.knocked_out.connect(on_ko, CONNECT_ONE_SHOT)
	dmg.apply_hit({"amount": amount, "zone": blow.zone, "attacker": attacker, "melee": true, "nonlethal": not blow.get("lethal", false),
		"weapon": "knife" if blow.get("lethal", false) else "fists",
		"position": t.global_position + Vector3(0, 1.5 if blow.zone == "head" else 1.2, 0), "direction": dir})
	if dmg.knocked_out.is_connected(on_ko):
		dmg.knocked_out.disconnect(on_ko)
	if blocked:
		attacker.set_meta("stagger_t", 0.5)          # a blocked blow leaves the attacker open
		_sound("punch_block", t.global_position + Vector3(0, 1.4, 0))
	else:
		t.set_meta("stagger_t", 0.35)
		_sound("punch_hit", t.global_position + Vector3(0, 1.5, 0))
	if ko[0]:
		knock_down(t, attacker)
	# a fistfight in town draws a crowd (residents gather and watch, src/ai/population.gd)
	if Game.population != null and Game.population.has_method("spectacle") and t.get_meta("_crowd_t", 0) < Time.get_ticks_msec():
		t.set_meta("_crowd_t", Time.get_ticks_msec() + 10000)
		Game.population.spectacle(t.global_position, 25.0, "fight")
	Game.log_event("melee", {"by": str(attacker.name), "kind": kind, "blocked": blocked, "ko": ko[0]})
	return {"hit": true, "blocked": blocked, "target": t, "amount": amount, "ko": ko[0]}

## Grapple (Melee while guarding): grab the person in front. A staggered, hurt or turned-away opponent is thrown down
## (a knockdown); anyone else is shoved back off balance. Returns {grabbed, thrown}.
static func grapple(attacker: Node3D, yaw: float) -> Dictionary:
	var t := target_for(attacker, yaw)
	attacker.set_meta("melee_t", 0.7)
	_animate(attacker, "cross", t)
	if t == null:
		return {"grabbed": false}
	var dmg = t.get("damageable")
	var hurt: bool = dmg.health < dmg.max_health * 0.5
	var staggered: bool = t.get_meta("stagger_t", 0.0) > 0.0
	var dir := t.global_position - attacker.global_position
	dir.y = 0.0
	dir = dir.normalized()
	var t_yaw: float = t.get("facing") if t.get("facing") != null else 0.0
	var turned := _forward(t_yaw).dot(-dir) < 0.2        # not facing the attacker
	var thrown := hurt or staggered or turned
	if thrown:
		dmg.apply_hit({"amount": 12.0, "zone": "chest", "attacker": attacker, "melee": true, "nonlethal": true,
			"position": t.global_position + Vector3(0, 1.0, 0), "direction": dir})
		knock_down(t, attacker)
	else:
		t.set_meta("stagger_t", 0.6)
		if t is CharacterBody3D:
			(t as CharacterBody3D).velocity += dir * 4.0
	_sound("punch_block" if not thrown else "punch_hit", t.global_position + Vector3(0, 1.2, 0))
	Game.log_event("grapple", {"by": str(attacker.name), "target": str(t.name), "thrown": thrown})
	return {"grabbed": true, "thrown": thrown, "target": t}

## Down for a few seconds (fall clip), then back up. People keep their fight-or-flight from the brain.
static func knock_down(n: Node3D, by: Node3D = null) -> void:
	n.set_meta("knocked_down", true)
	n.set_meta("blocking", false)
	var vis = n.get("visual")
	if vis != null and vis.has_method("play_action"):
		vis.play_action("death_back")
	Game.log_event("knockout", {"target": str(n.name), "by": str(by.name) if by else ""})
	var tree := n.get_tree()
	if tree == null:
		return
	tree.create_timer(4.0, false).timeout.connect(func():
		if not is_instance_valid(n) or n.get_meta("hogtied", false):
			return
		var v = n.get("visual")
		if v != null and v.has_method("play_action"):
			v.play_action("get_up_back")
		tree.create_timer(1.6, false).timeout.connect(func():
			if is_instance_valid(n):
				n.set_meta("knocked_down", false)))

static func is_down(n: Node) -> bool:
	return n != null and n.get_meta("knocked_down", false)

static func _animate(attacker: Node3D, kind: String, target: Node3D) -> void:
	var vis = attacker.get("visual")
	if vis == null:
		return
	var clip := "punch_" + kind
	if vis.has_method("play_action") and vis.get("anim") != null and vis.anim.has_animation(CharacterFactory.ANIM_LIB_NAME + "/" + clip):
		vis.play_action(clip, true)
		return
	var sk: Skeleton3D = vis.get("skeleton")
	if sk == null or sk.find_bone("RightHand") < 0:
		return
	var arm: MeleeArm = sk.get_node_or_null("MeleeArm")
	if arm == null:
		arm = MeleeArm.new()
		arm.name = "MeleeArm"
		sk.add_child(arm)
		arm.setup()
	var aim := attacker.global_position + _forward(attacker.get("facing") if attacker.get("facing") != null else 0.0) * 0.9 + Vector3(0, 1.45, 0)
	if target != null:
		aim = target.global_position + Vector3(0, 1.5 if kind != "body" else 1.15, 0)
	arm.throw(int(BLOWS.get(kind, BLOWS.jab).side), aim, float(BLOWS.get(kind, BLOWS.jab).time))

static func _sound(id: String, pos: Vector3) -> void:
	if Game.audio != null and Game.audio.has_sound(id):
		Game.audio.play(id, pos)
	elif Game.audio != null and id != "punch_whiff" and Game.audio.has_sound("impact_flesh"):
		Game.audio.play("impact_flesh", pos, {"volume_db": -4.0})
