extends Node
## A mission rider on horseback: a Horse (src/actors/horse.gd) led by its own call_to toward a moving marker, with a
## Human sat in the saddle (the person's own physics and brain paused while riding). Used for companions on the
## drive and riders Ruth escorts. ride_to(point), ride_with(node, offset), halt(), get_down().

var horse: Horse
var man: Human
var marker: Node3D
var follow_node: Node3D = null
var follow_offset := Vector3.ZERO
var halted := false
var riding := true

static func create(d, pos: Vector3, opts: Dictionary, breed := "mustang"):
	var o = load("res://src/missions/ch3/outrider.gd").new()
	o.name = "Outrider_%s" % str(opts.get("name", "Rider")).replace(" ", "")
	d.add_child(o)
	d.track(o)
	var hp := pos
	hp.y = Game.world.height(hp.x, hp.z)
	o.horse = Horse.spawn(int(opts.get("seed", 1)) + 7000, breed)
	Game.main.add_child(o.horse)
	o.horse.global_position = hp
	if Game.terrain:
		Game.terrain.ensure_collision_at(hp)
		Game.terrain.foci.append(o.horse)
	var g: Array = d.spawn_group(pos + Vector3(1.2, 0, 0), 1, opts, 0.1)
	o.man = g[0] if g.size() > 0 else null
	o.marker = Node3D.new()
	o.marker.name = "RideMarker"
	Game.main.add_child(o.marker)
	o.marker.global_position = hp
	o._seat()
	return o

func _seat() -> void:
	if man == null:
		return
	riding = true
	man.set_physics_process(false)
	if man.brain:
		man.brain.set_physics_process(false)
	man.collision_layer = 0
	man.collision_mask = 0
	man.intent.move_to = null

func ride_to(p: Vector3) -> void:
	follow_node = null
	halted = false
	marker.global_position = p

func ride_with(n: Node3D, offset := Vector3(4, 0, 3)) -> void:
	follow_node = n
	follow_offset = offset
	halted = false

func halt() -> void:
	halted = true
	if horse and horse.state == Horse.State.CALLED:
		horse.state = Horse.State.FREE
		horse.call_target = null

func teleport(p: Vector3) -> void:
	var q := p
	q.y = Game.world.height(q.x, q.z)
	if Game.terrain:
		Game.terrain.ensure_collision_at(q)
	horse.global_position = q
	marker.global_position = q
	horse.speed = 0.0

## Off the horse and back on foot (brain on); the horse stays where it is.
func get_down() -> void:
	if man == null or not riding:
		return
	riding = false
	halt()
	var p := horse.global_position + Vector3(cos(horse.yaw), 0, -sin(horse.yaw)) * -1.2
	p.y = Game.world.height(p.x, p.z) + 0.2
	man.global_position = p
	man.rotation = Vector3.ZERO
	man.collision_layer = 8
	man.collision_mask = 1 | 2 | 8
	man.set_physics_process(true)
	if man.brain:
		man.brain.set_physics_process(true)
		man.brain.home = p

func _physics_process(_dt: float) -> void:
	if horse == null or not is_instance_valid(horse):
		return
	if follow_node != null and is_instance_valid(follow_node):
		var b := follow_node.global_transform.basis
		marker.global_position = follow_node.global_position + Vector3(b.x.x, 0, b.x.z).normalized() * follow_offset.x \
			+ Vector3(b.z.x, 0, b.z.z).normalized() * follow_offset.z
	if not halted:
		var d := horse.global_position.distance_to(marker.global_position)
		if d > 5.0 and horse.state != Horse.State.CALLED and horse.state != Horse.State.RIDDEN:
			horse.call_to(marker)
	if riding and man != null and is_instance_valid(man) and man.alive and horse.visual:
		var seat: Transform3D = horse.visual.seat_transform()
		man.global_transform = Transform3D(Basis(Vector3.UP, horse.yaw), seat.origin - seat.basis.y.normalized() * Horse.SEAT_DROP)
		man.facing = horse.yaw
		if man.visual:
			man.visual.rotation = Vector3.ZERO
			if man.visual.has_method("set_locomotion"):
				man.visual.set_locomotion(0.0, "mounted", true)
	elif riding and man != null and is_instance_valid(man) and not man.alive:
		riding = false

func _exit_tree() -> void:
	if marker and is_instance_valid(marker):
		marker.queue_free()
	if horse and is_instance_valid(horse):
		if Game.terrain:
			Game.terrain.foci.erase(horse)
		horse.queue_free()
