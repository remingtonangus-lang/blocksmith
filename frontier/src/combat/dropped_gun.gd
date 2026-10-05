class_name DroppedGun
extends Node3D
## A gun knocked from someone's hand (a disarming shot to the arm) lying in the dirt: Interact picks it up into
## Ruth's arsenal with whatever was loaded in it.

var weapon := ""
var rounds := 0

static func drop(at: Vector3, weapon_id: String, loaded: int) -> DroppedGun:
	var g := DroppedGun.new()
	g.weapon = weapon_id
	g.rounds = loaded
	g.name = "Dropped_" + weapon_id
	Game.main.add_child(g)
	var p := at
	if Game.world:
		p.y = Game.world.height(p.x, p.z) + 0.04
	g.global_position = p
	g.rotation.y = randf() * TAU
	g._build()
	g.add_to_group("interactable")
	Game.log_event("gun_dropped", {"weapon": weapon_id})
	return g

func _build() -> void:
	var m: Node3D = null
	if ResourceLoader.exists("res://src/combat/weapon_model.gd") and not Game.headless:
		var wm = load("res://src/combat/weapon_model.gd")
		if wm.has_method("create"):
			m = wm.create(weapon)
	if m == null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var long: bool = Weapons.get_def(weapon).get("slot", "") == "longarm"
		bm.size = Vector3(0.05, 0.05, 1.0 if long else 0.3)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.15, 0.13)
		mat.metallic = 0.6
		mat.roughness = 0.45
		mi.material_override = mat
		m = mi
	m.rotation.z = PI * 0.5
	add_child(m)

func interact_prompt() -> String:
	return "Pick up the %s" % Weapons.get_def(weapon).get("name", "gun")

func interact(by: Node) -> void:
	var g = by.get("gun")
	if g == null:
		return
	if not g.weapons.has(weapon):
		g.weapons.append(weapon)
		g.clip[weapon] = rounds
	else:
		var ammo_kind: String = Weapons.get_def(weapon).get("ammo", "revolver")
		g.ammo[ammo_kind] = int(g.ammo.get(ammo_kind, 0)) + rounds
	Game.say("Picked up the %s." % Weapons.get_def(weapon).get("name", "gun"), 2.0)
	Game.log_event("gun_picked_up", {"weapon": weapon})
	queue_free()
