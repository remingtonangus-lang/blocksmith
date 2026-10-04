class_name Damageable
extends Node
## Health for anything that can be shot or hurt (people, horses, animals, bottles). Hitboxes are physics shapes on
## collision layer HITBOX with metadata {"damageable": this node, "zone": "head"/"chest"/...}; GunHandler resolves a
## raycast hit to `apply_hit`. Emits signals for reactions (stagger, flinch, ragdoll) and AI (threat memory).

signal damaged(info: Dictionary)
signal died(info: Dictionary)

const HITBOX_LAYER := 16

@export var max_health := 100.0
@export var armor := 0.0                 # flat reduction per hit
var health := 100.0
var alive := true
var last_attacker: Node = null
var kind := "human"                      # human / horse / animal / object
var regen_rate := 0.0                    # hp per second (player out of combat)
var _since_hit := 0.0

func _ready() -> void:
	health = max_health

func _process(dt: float) -> void:
	_since_hit += dt
	if alive and regen_rate > 0.0 and _since_hit > 6.0 and health < max_health:
		health = minf(health + regen_rate * dt, max_health)

## info: amount, zone, attacker, position, direction, weapon (id), impulse
func apply_hit(info: Dictionary) -> void:
	if not alive:
		return
	var zone: String = info.get("zone", "chest")
	var mult: float = Weapons.ZONES.get(zone, 1.0)
	var amount: float = maxf(float(info.get("amount", 10.0)) * mult - armor, 0.0)
	health -= amount
	_since_hit = 0.0
	last_attacker = info.get("attacker")
	info["final"] = amount
	info["zone"] = zone
	Game.log_event("hit", {"target": str(get_parent().name), "zone": zone, "amount": snappedf(amount, 0.1), "hp": snappedf(health, 0.1)})
	damaged.emit(info)
	if health <= 0.0:
		alive = false
		health = 0.0
		died.emit(info)

func heal(amount: float) -> void:
	if alive:
		health = minf(health + amount, max_health)

## Attach a capsule/box hitbox to a node (usually a BoneAttachment3D) for a zone.
static func make_hitbox(parent: Node3D, target: Damageable, zone: String, shape: Shape3D, offset := Transform3D.IDENTITY) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = HITBOX_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.set_meta("damageable", target)
	a.set_meta("zone", zone)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = offset
	a.add_child(cs)
	parent.add_child(a)
	return a
