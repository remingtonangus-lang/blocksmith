class_name PlayerCover
extends RefCounted
## Third-person cover for Ruth (Cover: X / RB). Press near a wall, crate, rock or low wall to tuck in:
## - low cover (chest height clear): crouched behind it; aiming pops up over the top,
## - high cover: pressed against it; aiming near an end peeks around that edge,
## - moving slides along the cover (it follows curved walls) and stops at the ends,
## - firing without aiming blind-fires over or around the cover (wide spread),
## - pushing away from the cover, sprinting or pressing Cover again leaves it.
## Hitboxes drop with the crouch, so low cover really covers. Probes use the world layer (terrain slopes don't count:
## a cover face must be steep).

const REACH := 1.25          # m: how far in front a cover face may be when entering
const GAP := 0.42            # m kept between the body centre and the face
const LOW_H := 0.55          # probe heights (m above the feet)
const HIGH_H := 1.35
const PEEK := 0.6            # m stepped out around an edge when aiming at high cover
const SLIDE := 1.7           # m/s along the cover

var p: CharacterBody3D
var active := false
var low := false
var normal := Vector3.FORWARD     # out of the face, toward Ruth (horizontal)
var edge := 0                     # -1 / +1 when an end of the cover is within reach on that side (along tangent)
var peek_t := 0.0
var _peek_side := 0               # side the current peek steps toward (kept while peeking)
var _away_t := 0.0
var enters := 0

func _init(player: CharacterBody3D) -> void:
	p = player

func tangent() -> Vector3:
	return Vector3.UP.cross(normal).normalized()      # Ruth's right when facing the cover

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q)

## Cover face straight ahead of `dir` at height h, or {} (faces must be steep: |n.y| < 0.45).
func _face(origin: Vector3, dir: Vector3, h: float, reach := REACH) -> Dictionary:
	var from := origin + Vector3(0, h, 0)
	var hit := _ray(from, from + dir * reach)
	if hit.is_empty() or absf(hit.normal.y) > 0.45:
		return {}
	return hit

## Try to enter cover facing `dir` (camera forward on the ground plane). True when Ruth tucked in.
func try_enter(dir: Vector3) -> bool:
	dir.y = 0.0
	dir = dir.normalized()
	var best := {}
	# straight ahead first, then a fan, so a crate a little off-centre still counts
	for a in [0.0, 0.35, -0.35, 0.7, -0.7]:
		best = _face(p.global_position, dir.rotated(Vector3.UP, a), LOW_H)
		if not best.is_empty():
			break
	if best.is_empty():
		return false
	normal = Vector3(best.normal.x, 0.0, best.normal.z).normalized()
	low = _face(p.global_position, -normal, HIGH_H, REACH + 0.3).is_empty()
	active = true
	enters += 1
	_away_t = 0.0
	Game.log_event("cover", {"low": low})
	return true

func leave() -> void:
	active = false
	peek_t = 0.0
	edge = 0
	_peek_side = 0

## Movement while in cover. Returns the horizontal velocity; updates facing / crouch / edge / peek.
func step(dt: float, want_dir: Vector3, aiming: bool, sprint: bool) -> Vector3:
	var t := tangent()
	# probes run from the anchor (where Ruth stands when not peeking), so a peek past the end keeps the cover
	var pos := p.global_position - t * _peek_side * PEEK * peek_t
	# follow the face (curved walls, angled crates); lose it -> out of cover
	var hit := _face(pos, -normal, LOW_H, GAP + 0.6)
	if hit.is_empty():
		leave()
		return Vector3.ZERO
	normal = Vector3(hit.normal.x, 0.0, hit.normal.z).normalized()
	t = tangent()
	low = _face(pos, -normal, HIGH_H, GAP + 0.7).is_empty()
	# edges: does the cover continue half a metre to each side?
	edge = 0
	for side in [-1, 1]:
		if _face(pos + t * side * 0.55, -normal, LOW_H if low else HIGH_H, GAP + 0.7).is_empty():
			edge = side
	# leaving: push away from the cover for a moment, or sprint
	var away := want_dir.dot(normal)
	_away_t = _away_t + dt if away > 0.7 else 0.0
	if _away_t > 0.2 or (sprint and want_dir != Vector3.ZERO):
		leave()
		return want_dir * 2.5
	var v := Vector3.ZERO
	if not aiming and want_dir != Vector3.ZERO:
		var s := want_dir.dot(t)
		if absf(s) > 0.25:
			var side := int(signf(s))
			if not _face(pos + t * side * 0.45, -normal, LOW_H, GAP + 0.7).is_empty():   # cover continues that way
				v = t * side * SLIDE * clampf(absf(s), 0.4, 1.0)
	# hold the gap to the face
	var here := p.global_position
	var dist := (here - Vector3(hit.position.x, here.y, hit.position.z)).dot(normal)
	v += normal * clampf((GAP - dist) * 8.0, -2.0, 2.0)
	# peeking around an edge of high cover while aiming
	if peek_t <= 0.0:
		_peek_side = edge
	var want_peek := 1.0 if aiming and not low and _peek_side != 0 else 0.0
	var prev := peek_t
	peek_t = move_toward(peek_t, want_peek, dt * 5.0)
	if _peek_side != 0:
		v += t * _peek_side * PEEK * (peek_t - prev) / maxf(dt, 0.001)
	return v

## Facing (yaw) while in cover: toward the cover face, along the slide direction, or the camera when aiming.
func facing(v: Vector3, aiming: bool, cam_yaw: float) -> float:
	if aiming:
		return cam_yaw
	var tv := v - normal * v.dot(normal)
	if tv.length() > 0.3:
		return atan2(-tv.x, -tv.z)
	return atan2(normal.x, normal.z)        # facing the face (forward = -normal)

## Where a blind-fired shot leaves from: over the top of low cover, around the edge of high cover.
func blind_muzzle() -> Vector3:
	var pos := p.global_position
	if low:
		return pos + Vector3(0, 1.25, 0) - normal * 0.15
	var side := edge if edge != 0 else 1
	return pos + Vector3(0, 1.45, 0) + tangent() * side * 0.45 - normal * 0.1

func crouched(aiming: bool) -> bool:
	return active and low and not aiming
