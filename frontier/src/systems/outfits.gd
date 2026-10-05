extends Node
## Outfit items change Ruth's look. Each legendary outfit retints garments on her character (CharacterFactory look:
## surfaces whose source material is "cloth:hat:*", "leather:vest:*", "cloth:shirt:*" get their own copy of the
## shared cloth material with a new tint), or on the stand-in figure (its hat disc and body capsule). Wear and take
## off from the satchel; the choice is kept in WorldState (flags "outfit_worn") and re-applied when Ruth's figure is
## rebuilt. apply() returns how many surfaces it changed (bots check it).

const LOOKS := {
	"grey_widow": {"name": "Grey Widow Coat", "parts": {"vest": Color(0.62, 0.62, 0.6), "shirt": Color(0.78, 0.78, 0.76)}},
	"ironhide": {"name": "Ironhide Bearskin Coat", "parts": {"vest": Color(0.13, 0.09, 0.07), "shirt": Color(0.42, 0.32, 0.24)}},
	"pale_ghost": {"name": "Pale Ghost Hat Band and Vest", "parts": {"hat": Color(0.86, 0.82, 0.74), "vest": Color(0.8, 0.76, 0.68)}},
	"sable_king": {"name": "Sable King Gloves and Riding Hat", "parts": {"hat": Color(0.4, 0.26, 0.15), "belt": Color(0.36, 0.22, 0.12)}},
}

var _applied_to: Node = null
var _t := 1.0

func _ready() -> void:
	Game.set_meta("outfits", self)

static func worn() -> String:
	return str(Game.state.flags.get("outfit_worn", "")) if Game.state else ""

static func owned(id: String) -> bool:
	return Game.state != null and int(Game.state.inventory.get("outfit_" + id, 0)) > 0

func wear(id: String) -> int:
	if not owned(id) or not LOOKS.has(id):
		return 0
	Game.state.flags["outfit_worn"] = id
	var n := apply(Game.player)
	Game.log_event("outfit_worn", {"id": id, "surfaces": n})
	Game.say("You put on the %s." % LOOKS[id].name, 2.5)
	return n

func take_off() -> int:
	if Game.state:
		Game.state.flags.erase("outfit_worn")
	var n := apply(Game.player)
	Game.log_event("outfit_worn", {"id": "", "surfaces": n})
	return n

## Re-dress Ruth's figure for the outfit worn now (or her own clothes). Returns surfaces changed.
func apply(p: Node) -> int:
	if p == null or p.get("visual") == null:
		return 0
	var v: Node3D = p.visual
	_applied_to = v
	var id := worn()
	var parts: Dictionary = LOOKS.get(id, {}).get("parts", {})
	var n := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = mi
		if m3.mesh == null:
			continue
		for s in m3.mesh.get_surface_count():
			var src: Material = m3.mesh.surface_get_material(s)
			var key := src.resource_name if src else ""
			var part := ""
			if key.contains(":"):
				part = key.get_slice(":", 1)
			if part != "":
				# a generated character: garments by their material key
				var shared: Material = m3.get_surface_override_material(s)
				if m3.has_meta("outfit_base_%d" % s):
					shared = m3.get_meta("outfit_base_%d" % s)
				if parts.has(part) and shared is ShaderMaterial:
					if not m3.has_meta("outfit_base_%d" % s):
						m3.set_meta("outfit_base_%d" % s, shared)
					var mine: ShaderMaterial = shared.duplicate()
					var c: Color = parts[part]
					mine.set_shader_parameter("tint", c)
					mine.set_shader_parameter("tint_slot", -1)
					m3.set_surface_override_material(s, mine)
					n += 1
				elif m3.has_meta("outfit_base_%d" % s):
					m3.set_surface_override_material(s, m3.get_meta("outfit_base_%d" % s))
					m3.remove_meta("outfit_base_%d" % s)
			elif m3.material_override is StandardMaterial3D:
				# the stand-in figure: the disc is the hat, the capsule is coat and all
				var slot := "hat" if m3.mesh is CylinderMesh else ("vest" if m3.mesh is CapsuleMesh else "")
				if slot == "":
					continue
				var smat: StandardMaterial3D = m3.material_override
				if not m3.has_meta("outfit_base_col"):
					m3.set_meta("outfit_base_col", smat.albedo_color)
				var col: Color = parts.get(slot, m3.get_meta("outfit_base_col"))
				if parts.has(slot):
					n += 1
				var nm: StandardMaterial3D = smat.duplicate()
				nm.albedo_color = col
				m3.material_override = nm
	return n

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 2.0
	# Ruth's figure can be rebuilt (look streaming, respawn): dress the new one
	var p = Game.player
	if p != null and p.get("visual") != null and p.visual != _applied_to and worn() != "":
		apply(p)
