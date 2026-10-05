class_name AudioLocomotion
extends Node
## Footsteps, hoofbeats and tack. The player is tracked automatically (stride from distance travelled and gait,
## landings from air time); NPCs and horses either call AudioDirector.footstep/hoof directly from animation events or
## are registered with track_actor()/track_horse() and get the same automatic treatment.
## Hooves follow real gait rhythms per stride: walk 4-beat, trot 2-beat (diagonal pairs), canter 3-beat + suspension,
## gallop 4-beat (rotary) + suspension; force rises with gait. Tack creaks and jingles with the stride; the horse
## breathes once per gallop stride.

const STRIDE := {"walk": 0.72, "jog": 1.05, "sprint": 1.45}       # metres per footstep
# hoof gait: stride period (s) at reference speed, beat offsets as fraction of the stride, force
const GAITS := {
	"walk": {"speed": 1.7, "period": 1.05, "beats": [0.0, 0.25, 0.5, 0.75], "force": "soft"},
	"trot": {"speed": 3.8, "period": 0.68, "beats": [0.0, 0.015, 0.5, 0.515], "force": "soft"},
	"canter": {"speed": 6.5, "period": 0.6, "beats": [0.0, 0.17, 0.2, 0.36], "force": "hard"},
	"gallop": {"speed": 12.0, "period": 0.44, "beats": [0.0, 0.09, 0.21, 0.29], "force": "hard"},
}

var director: Node
var _player_accum := 0.0
var _player_last := Vector3.INF
var _player_air := 0.0
var _player_was_floor := true
var _actors: Array = []          # [{node, accum, last}]
var _horses: Array = []          # [{node, phase, beat, last_pos, breath}]
var _rng := RandomNumberGenerator.new()
var steps_played := 0
var hooves_played := 0
var last_surface := ""

func _ready() -> void:
	director = get_parent()
	_rng.seed = 4242

## Generic footstep at a position. surface "" = detect; gait: walk/run/land/scuff.
func footstep(pos: Vector3, surface := "", gait := "walk", volume_db := 0.0) -> void:
	var s: String = surface if not surface.is_empty() else director.surface_at(pos)
	last_surface = s
	var id := "step_%s_%s" % [s, gait]
	if not director.has_sound(id):
		id = "step_dirt_" + gait
	director.play(id, pos, {"volume_db": volume_db})
	steps_played += 1
	if (s == "wood" or s == "stone") and gait != "land" and _rng.randf() < 0.35:
		director.play("spur_jingle", pos, {"volume_db": -4.0})

## One hoof contact. force: soft/hard.
func hoof(pos: Vector3, surface := "", force := "soft", volume_db := 0.0) -> void:
	var s: String = surface if not surface.is_empty() else director.surface_at(pos)
	var id := "hoof_%s_%s" % [s, force]
	if not director.has_sound(id):
		id = "hoof_dirt_" + force
	director.play(id, pos, {"volume_db": volume_db})
	hooves_played += 1

func track_actor(node: Node3D) -> void:
	_actors.append({"node": node, "accum": 0.0, "last": node.global_position})

## Register a horse (any Node3D; reads `gait` (walk/trot/canter/gallop) and `speed` properties if present, else
## derives them from its motion). Rider tack sounds play when `rider` is set or it is the player's horse.
func track_horse(node: Node3D) -> void:
	for h in _horses:
		if h.node == node:
			return
	_horses.append({"node": node, "phase": 0.0, "beat": 0, "last_pos": node.global_position, "breath": 0.0,
		"speed": 0.0})

func untrack(node: Node) -> void:
	_actors = _actors.filter(func(a): return a.node != node)
	_horses = _horses.filter(func(h): return h.node != node)

func _physics_process(dt: float) -> void:
	_player(dt)
	for a in _actors:
		var nd = a.node
		if not is_instance_valid(nd):
			continue
		var p: Vector3 = (nd as Node3D).global_position
		var d := Vector2(p.x - a.last.x, p.z - a.last.z).length()
		a.last = p
		if d > 3.0:            # teleport
			continue
		a.accum += d
		var spd := d / maxf(dt, 0.0001)
		var gait := "walk" if spd < 2.4 else "run"
		var stride: float = STRIDE.walk if gait == "walk" else STRIDE.jog
		if a.accum >= stride:
			a.accum = 0.0
			footstep(p, "", gait, -2.0)
	var pl = Game.player
	if pl != null and pl.get("on_horse") != null:
		track_horse(pl.on_horse)
	for h in _horses:
		_horse(h, dt)

func _player(dt: float) -> void:
	var pl = Game.player
	if pl == null or not (pl is CharacterBody3D) or not is_instance_valid(pl):
		return
	if pl.get("on_horse") != null:
		_player_last = Vector3.INF
		return
	var body := pl as CharacterBody3D
	var p := body.global_position
	var on_floor := body.is_on_floor()
	if not on_floor:
		_player_air += dt
	else:
		if not _player_was_floor and _player_air > 0.35:
			footstep(p, "", "land", 0.0)
			_player_accum = 0.0
		_player_air = 0.0
	_player_was_floor = on_floor
	if _player_last == Vector3.INF:
		_player_last = p
		return
	var d := Vector2(p.x - _player_last.x, p.z - _player_last.z).length()
	_player_last = p
	if d > 3.0 or not on_floor:
		return
	_player_accum += d
	var gait: String = str(pl.get("gait")) if pl.get("gait") != null else "walk"
	if gait == "idle":
		if _player_accum > 0.4:        # shuffling in place
			_player_accum = 0.0
			footstep(p, "", "scuff", -6.0)
		return
	var stride: float = STRIDE.get(gait, 0.8)
	if _player_accum >= stride:
		_player_accum -= stride
		var crouch := false
		if pl.get("intent") is Dictionary:
			crouch = bool(pl.intent.get("crouch", false))
		footstep(p, "", "walk" if gait == "walk" else "run", -6.0 if crouch else 0.0)

func _horse(h: Dictionary, dt: float) -> void:
	var nd = h.node
	if not is_instance_valid(nd):
		return
	var node := nd as Node3D
	var p := node.global_position
	var moved := Vector2(p.x - h.last_pos.x, p.z - h.last_pos.z).length()
	h.last_pos = p
	var spd: float
	if node.get("speed") != null:
		spd = float(node.get("speed"))
	else:
		spd = moved / maxf(dt, 0.0001)
		h.speed = lerpf(float(h.speed), spd, 1.0 - exp(-6.0 * dt))
		spd = h.speed
	if spd < 0.3:
		h.phase = 0.0
		h.beat = 0
		return
	var gait: String = str(node.get("gait")) if node.get("gait") != null else ""
	if not GAITS.has(gait):
		gait = "walk" if spd < 2.6 else ("trot" if spd < 5.0 else ("canter" if spd < 8.5 else "gallop"))
	var g: Dictionary = GAITS[gait]
	# stride period scales gently with speed within a gait
	var period: float = g.period * clampf(sqrt(g.speed / maxf(spd, 0.5)), 0.8, 1.25)
	var prev: float = h.phase
	h.phase = prev + dt / period
	var beats: Array = g.beats
	var fwd := -node.global_transform.basis.z
	var side := node.global_transform.basis.x
	# feet: LH, LF, RH, RF positions around the body
	var feet := [p - fwd * 0.9 - side * 0.3, p + fwd * 0.9 - side * 0.3, p - fwd * 0.9 + side * 0.3, p + fwd * 0.9 + side * 0.3]
	for i in beats.size():
		var bt: float = beats[i]
		if _crossed(prev, h.phase, bt):
			var fp: Vector3 = feet[i % 4]
			fp.y = p.y
			hoof(fp, "", g.force, 0.0 if gait != "walk" else -3.0)
	if _crossed(prev, h.phase, 0.62) and _rng.randf() < (0.35 if gait == "walk" else 0.6):
		director.play("saddle_creak", p + Vector3.UP * 1.2, {"volume_db": -3.0 if gait == "walk" else 0.0})
	if gait != "walk" and _crossed(prev, h.phase, 0.4) and _rng.randf() < 0.4:
		director.play("bridle_jingle", p + fwd * 1.0 + Vector3.UP * 1.5)
	if (gait == "gallop" or gait == "canter") and _crossed(prev, h.phase, 0.05):
		director.play("horse_breath", p + fwd * 1.2 + Vector3.UP * 1.4, {"volume_db": -6.0, "pitch": 1.2})
	if h.phase >= 1.0:
		h.phase -= 1.0

static func _crossed(a: float, b: float, t: float) -> bool:
	var fa := fposmod(a, 1.0)
	var fb := fa + (b - a)
	return (fa <= t and fb > t) or (fa <= t + 1.0 and fb > t + 1.0)
