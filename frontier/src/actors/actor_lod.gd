class_name ActorLOD
extends RefCounted
## Physics LOD for people and animals: beyond PHYSICS_RANGE of the player (and of the camera, for cutscenes) bodies
## don't run move_and_slide; they glide along the heightmap at their intended velocity. Costs ~nothing, never falls
## through unloaded collision tiles, and hands back to full physics seamlessly as Ruth approaches.

const PHYSICS_RANGE := 60.0

static func far(body: Node3D) -> bool:
	if Game.args.has("no_actor_lod"):
		return false
	# no collision under the body yet (tiles stream in a couple per frame): glide rather than fall
	if Game.terrain and not Game.terrain.has_collision_at(body.global_position):
		return true
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return false
	var r2 := PHYSICS_RANGE * PHYSICS_RANGE
	if body.global_position.distance_squared_to(p.global_position) < r2:
		return false
	var cam: Camera3D = Game.camera
	if cam and body.global_position.distance_squared_to(cam.global_position) < r2:
		return false
	return true

static func glide(body: CharacterBody3D, dt: float) -> void:
	var pos := body.global_position + Vector3(body.velocity.x, 0.0, body.velocity.z) * dt
	pos.y = Game.world.height(pos.x, pos.z)
	body.global_position = pos
	body.velocity.y = 0.0
