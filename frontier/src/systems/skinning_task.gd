class_name SkinningTask
extends Node
## Skinning a carcass: Ruth kneels at the animal (held in place via player.busy), works for a few seconds
## (bend-down clip, then a crouch with the knife hand moving), and the carcass changes (lying pose, skinned
## shader state); the pelt and meat go into the satchel. Interrupted if she is hurt or the carcass is gone.
## API: SkinningTask.start(player, animal) -> SkinningTask (null if busy).

const DURATION := 3.2

var player: Node3D
var animal: Node3D
var t := 0.0
var done := false
var result := {}

static func start(p: Node3D, a: Node3D) -> SkinningTask:
	if p == null or a == null or p.get("busy") != null:
		return null
	var k := SkinningTask.new()
	k.player = p
	k.animal = a
	k.name = "SkinningTask"
	p.add_child(k)
	return k

func _ready() -> void:
	player.set("busy", self)
	# face the carcass and kneel beside it
	var to: Vector3 = animal.global_position - player.global_position
	to.y = 0.0
	if to.length() > 0.1 and player.get("facing") != null:
		player.set("facing", atan2(-to.x, -to.z))
	var vis = player.get("visual")
	if vis != null and vis.has_method("play_action"):
		vis.play_action("pick_up")
	if vis != null and vis.has_method("set_activity"):
		vis.set_activity("idle_crouch")          # kneel / crouch held between the working motions
	if Game.hud:
		Game.hud.notice("Skinning the %s..." % str(animal.get("spec").name).to_lower(), DURATION)
	Game.log_event("skinning_start", {"species": str(animal.get("species"))})

func _process(dt: float) -> void:
	if done:
		return
	t += dt
	if not is_instance_valid(animal) or (player.get("health") != null and float(player.get("health")) <= 0.0):
		_finish(false)
		return
	var vis = player.get("visual")
	if vis != null and vis.has_method("play_action") and fmod(t, 1.2) < dt:
		vis.play_action("pick_up")          # the working motion: reach down, pull, again
	if t >= DURATION:
		_finish(true)

func _finish(ok: bool) -> void:
	done = true
	if ok and animal.has_method("skin"):
		result = animal.skin()
		if not result.is_empty() and Game.hud:
			Game.hud.notice("%s pelt — %s" % [animal.get("spec").name, ["", "poor", "good", "perfect"][int(result.quality)]], 3.5)
	if player.get("busy") == self:
		player.set("busy", null)
	var vis = player.get("visual")
	if vis != null and vis.has_method("set_activity"):
		vis.set_activity("")
	queue_free()
