class_name VRShots
extends RefCounted
## Scripted VR scenes for evidence shots (`--vr_sim`): poses the simulated head and hands through VRSim and works
## the real VR code paths (VRPlay draws, fires, reloads, marks, takes the reins). Shared by the in-world feature
## shots (src/tests/feature_shots.gd) and the light studio set (src/tests/vr_studio.gd). The host provides
##   _settle(frames), _ground(x, z) -> float, _vr_target(pos: Vector3, seed: int) -> Node3D
## and places the player before each scene; `yaw` is the facing in degrees clockwise from -Z (as feature shots).

var host: Node

func _init(h: Node) -> void:
	host = h

func vr() -> VR:
	if Game.player == null:
		return null
	for c in Game.player.get_children():
		if c is VR:
			return c
	return null

## Origin-local helpers: the head stands at 1.62 m looking along -Z (yaw/pitch in degrees, + = right/up).
static func head(yaw := 0.0, pitch := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)), Vector3(0, 1.62, 0))

static func aim(pos: Vector3, yaw := 0.0, pitch := 0.0, roll := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.FORWARD, deg_to_rad(roll)), pos)

static func rest_left() -> Transform3D:
	return aim(Vector3(-0.22, 1.0, -0.12), 0, -60)

static func rest_right() -> Transform3D:
	return aim(Vector3(0.22, 1.0, -0.12), 0, -60)

func pose(yaw_deg: float, h: Transform3D, l: Transform3D, r: Transform3D) -> void:
	var v := vr()
	v.origin.global_rotation = Vector3(0, deg_to_rad(-yaw_deg), 0)
	v.sim.set_pose(h, l, r)

func to_local(world: Vector3) -> Vector3:
	return vr().origin.global_transform.affine_inverse() * world

func ahead(yaw_deg: float, d: float, side := 0.0) -> Vector3:
	var p: Vector3 = Game.player.global_position
	var f := Vector3(sin(deg_to_rad(yaw_deg)), 0, -cos(deg_to_rad(yaw_deg)))
	var r := Vector3(-f.z, 0, f.x)
	var q := p + f * d + r * side
	q.y = host._ground(q.x, q.z)
	return q

func reset() -> void:
	var v := vr()
	if v == null:
		return
	v.sim.clear_inputs()
	v.play.holding = false
	v.play.two_hand = false
	if v.play._gate_open:
		v.play._close_reload()
	v.play._drop_round()
	var pl = Game.player
	pl.gun.drawn = false
	pl.intent.aim = false
	for w in pl.gun.weapons:                    # every scene starts with full guns
		pl.gun.clip[w] = int(Weapons.get_def(w).get("capacity", 6))
	if pl.nerve and pl.nerve.active:
		pl.nerve.deactivate()

## Draw a weapon slot the physical way: put the right hand on its holstered grip, squeeze, then bring it up.
func draw(slot: int, yaw_deg: float) -> WeaponModel:
	var v := vr()
	var pl = Game.player
	if pl.holder == null:
		return null
	var id: String = pl.gun.weapons[slot]
	var wm: WeaponModel = pl.holder.models.get(id)
	if wm == null:
		return null
	pose(yaw_deg, head(), rest_left(), rest_right())
	pl.holder.snap = true                 # everything back in its holster now (no blend from the last scene)
	await host._settle(3)
	pl.holder.snap = false
	var at := to_local(wm.grip_transform("grip_r").origin)
	if Game.args.has("vr_debug"):
		print("  dbg draw %s holster grip %s local %s model %s" % [id, wm.grip_transform("grip_r").origin, at, wm.global_position])
	v.sim.set_pose(head(), rest_left(), VRSim.grip_to_aim(Transform3D(Basis.IDENTITY, at)))
	await host._settle(3)
	v.sim.set_input("right", &"grip", 1.0)
	await host._settle(4)
	return pl.holder.model() if v.play.holding else null

## Right-hand aim frame that puts the gun's rear sight on the eye line, `d` metres in front of the eye.
static func sight_hand(m: WeaponModel, h: Transform3D, d: float) -> Transform3D:
	var g := m.marker_local("grip_r").origin
	var sr := m.marker_local("sight_rear").origin if m.marker("sight_rear") != null else g + Vector3(0, 0.03, 0.0)
	var b := h.basis
	return Transform3D(b, h.origin - b.z * d - b * (sr - g))

func targets(yaw: float) -> Array:
	var foes: Array = []
	for i in 3:
		foes.append(host._vr_target(ahead(yaw, 12.0 + i * 4.0, -3.5 + i * 3.5), 500 + i))
	return foes

# ------------------------------------------------------------------ scenes
func hud(yaw: float) -> void:
	pose(yaw, head(0, -4), rest_left(), rest_right())
	await host._settle(20)

func menu(yaw: float) -> void:
	pose(yaw, head(), rest_left(), aim(Vector3(0.18, 1.3, -0.3), -7, 9))
	await host._settle(10)
	Game.menus.open_pause()
	await host._settle(20)

func hands(yaw: float) -> void:
	var v := vr()
	# left hand open, palm in; right hand pointing (grip squeezed, index out)
	pose(yaw, head(0, -22), aim(Vector3(-0.1, 1.42, -0.34), 25, 10, -20), aim(Vector3(0.12, 1.4, -0.36), -15, 5, 10))
	v.sim.set_input("right", &"grip", 1.0)
	v.sim.set_input("left", &"trigger", 0.3)
	await host._settle(30)

func gun_aim(yaw: float, fire := false) -> void:
	targets(yaw)
	await host._settle(10)
	var m := await draw(0, yaw)
	if m == null:
		return
	var h := head(-3, -2)
	var v := vr()
	v.sim.set_pose(h, aim(Vector3(-0.25, 1.05, -0.2), 0, -40), sight_hand(m, h, 0.5))
	await host._settle(10)
	if fire:
		v.sim.set_input("right", &"trigger", 1.0)       # one shot: flash, smoke, recoil, haptics
		await host._settle(1)

func two_hand(yaw: float) -> void:
	targets(yaw)
	await host._settle(10)
	var m := await draw(1, yaw)
	if m == null:
		return
	var v := vr()
	var h := head(0, -2)
	var r := sight_hand(m, h, 0.34)
	# support hand on the fore-end (grip_l) of the gun as the right hand holds it
	var gl: Vector3 = r * (m.marker_local("grip_l").origin - m.marker_local("grip_r").origin)
	v.sim.set_pose(h, VRSim.grip_to_aim(Transform3D(r.basis * Basis(Vector3.FORWARD, deg_to_rad(-70)), gl)), r)
	await host._settle(3)
	v.sim.set_input("left", &"grip", 1.0)
	await host._settle(10)

func reload(yaw: float) -> void:
	var v := vr()
	var pl = Game.player
	pl.gun.clip[pl.gun.weapons[0]] = 2
	var m := await draw(0, yaw)
	if m == null:
		return
	var h := head(0, -38)
	# roll the revolver onto its left side in front of the chest: the gate opens
	var r := aim(Vector3(0.04, 1.28, -0.34), 15, 10, -80)
	v.sim.set_pose(h, rest_left(), r)
	await host._settle(30)
	# take a round from the belt with the left hand...
	v.sim.set_pose(h, VRSim.grip_to_aim(Transform3D(Basis.IDENTITY, to_local(v.play._belt_point()))), r)
	await host._settle(3)
	v.sim.set_input("left", &"grip", 1.0)
	await host._settle(3)
	# ...and bring it up to the open gate (just short, so the shot shows the round in the fingers)
	var gate := to_local(v.play._port(m))
	v.sim.set_pose(h, aim(gate + Vector3(-0.07, -0.03, 0.1), 40, 20, -30), r)
	await host._settle(12)

func nerve(yaw: float) -> void:
	var foes := targets(yaw)
	await host._settle(10)
	var m := await draw(0, yaw)
	if m == null:
		return
	var v := vr()
	var h := head(-3, -2)
	v.sim.set_pose(h, rest_left(), sight_hand(m, h, 0.5))
	await host._settle(4)
	v.sim.set_input("left", &"by_button", true)
	await host._settle(3)
	v.sim.set_input("left", &"by_button", false)
	# point at two of them and squeeze: marks
	for f in foes.slice(0, 2):
		if f == null:
			continue
		var to := to_local((f as Node3D).global_position + Vector3(0, 1.45, 0))
		var b := Basis.looking_at((to - h.origin).normalized(), Vector3.UP)
		v.sim.set_pose(h, rest_left(), sight_hand(m, Transform3D(b, h.origin), 0.5))
		await host._settle(3)
		v.sim.set_input("right", &"trigger", 1.0)
		await host._settle(2)
		v.sim.set_input("right", &"trigger", 0.0)
		await host._settle(2)
	v.sim.set_pose(h, rest_left(), sight_hand(m, h, 0.5))
	await host._settle(6)

func riding() -> void:
	var v := vr()
	var hz: Horse = Horse.player_horse
	var yaw := -rad_to_deg(hz.yaw) if hz else 0.0
	pose(yaw, head(0, -30), aim(Vector3(-0.11, 1.24, -0.4), 0, -15, -15), aim(Vector3(0.11, 1.24, -0.4), 0, -15, 15))
	v.sim.set_input("left", &"grip", 1.0)
	v.sim.set_input("right", &"grip", 1.0)
	await host._settle(30)

## Reach toward an interactable (a door here) with the left hand: the HUD prompts, a squeeze opens it.
func reach(yaw: float, target: Vector3, squeeze := true) -> void:
	var v := vr()
	pose(yaw, head(0, -14), rest_left(), rest_right())
	await host._settle(3)
	var at := to_local(target)
	v.sim.set_pose(head(0, -14), aim(at + Vector3(0.0, 0.0, 0.08), 10, 0, -80), rest_right())
	await host._settle(6)
	if squeeze:
		v.sim.set_input("left", &"grip", 1.0)
		await host._settle(20)
