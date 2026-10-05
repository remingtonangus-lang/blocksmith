extends Mission
## Stranger — The Comet (eerie, sad). Silas Wren, a hermit astronomer turned out of the Naval Observatory, has
## figured a comet for tonight from his rock above the Kestrel trapper's cabin. Catch his supper from the creek, carry
## the lens up to the high rock, and stay the night with him or ride on. If she stays, the comet comes, and he goes
## with it. Reads posed_for_novel (he's had the dime novel in the mail). Flag: stayed_for_comet.

const ST = preload("res://src/missions/strangers/st.gd")
const C2 = preload("res://src/missions/ch2/ch2.gd")
const C3 = preload("res://src/missions/ch3/ch3.gd")
const C4 = preload("res://src/missions/ch4/ch4.gd")
const PHOTO = preload("res://src/missions/strangers/hold_still.gd")

func _init() -> void:
	id = "s_comet"
	title = "The Comet"
	chapter = 4
	stranger = true
	region = "Kestrel Range"
	requires = ["c4_coldwater"]
	start_pos = Mission.place("trapper_cabin_n", 8.0, 6.0)

func run(d) -> Variant:
	d.set_time(18.2)
	d.set_weather("clear")
	d.set_snow(0.0)
	var cabin := C3.dry(Mission.place("trapper_cabin_n", 8.0, 6.0))
	await C3.start_at(d, C2.near(cabin, -4.0, 3.0), cabin, false)
	var wren := ST.person(d, cabin, {"role": "prospector", "name": "Silas Wren", "seed": 9501})
	d.cine_begin()
	await d.say("s_comet_01", wren)
	await d.say("s_comet_02", Game.player)
	await d.say("s_comet_03", wren)
	d.cine_end()
	d.checkpoint("supper")
	var caught: String = await ST.fish(d, cabin, "Catch Mr. Wren a trout for supper")
	if d.aborted(): return false
	Game.log_event("comet_supper", {"fish": caught})
	await d.goto(C2.near(cabin, -2.0, 1.0), 4.0, "Bring the fish up to the cabin")
	if d.aborted(): return false
	d.npc_hold(wren, Game.player.global_position)
	d.set_time(20.5)
	d.cine_begin()
	await d.say("s_comet_04", wren)
	if ST.flag("posed_for_novel"):
		await d.say("s_comet_15", wren)
	await d.say("s_comet_05", wren)
	await d.say("s_comet_06", wren)
	d.cine_end()
	d.checkpoint("lens")
	var rock := PHOTO.high_ground(cabin, 120.0)
	var foot := C3.dry(cabin.lerp(rock, 0.55))
	await d.goto(foot, 5.0, "Carry the lens up toward the high rock")
	if d.aborted(): return false
	await d.climb(C4.holds(foot, rock, 4), "Climb the last of it with the lens")
	if d.aborted(): return false
	d._put_on_ground(wren, C2.near(rock, -2.0, 1.5))
	d.npc_hold(wren, rock + Vector3(0, 0, -40.0))
	d.cine_begin()
	await d.say("s_comet_07", wren)
	var pick: int = await d.choose("An old man on a cold rock, waiting for a comet nobody else believes in.",
		["Stay the night with him.", "Ride on before the cold sets in."])
	var stayed := pick == 0
	ST.set_flag("stayed_for_comet", stayed)
	if stayed:
		await d.say("s_comet_08", Game.player)
		d.cine_end()
		d.set_time(2.25)
		_comet(d, rock)
		d.cine_begin()
		await d.say("s_comet_09", wren)
		await d.say("s_comet_10", Game.player)
		await d.say("s_comet_11", wren)
		d.cine_end()
		if wren:
			wren.intent.crouch = true
		await d.wait(3.0)
		d.set_time(5.6)
		await d.say("s_comet_12", Game.player)
		ST.set_flag("wren_dead", true)
		ST.standing(1.0, "kept a dying man company")
	else:
		await d.say("s_comet_13", Game.player)
		await d.say("s_comet_14", wren)
		d.cine_end()
	return true

## The comet: a pale streak with a long tail low over the ridge (a sky prop; skipped headless).
func _comet(d, from: Vector3) -> void:
	if Game.headless:
		return
	var n := Node3D.new()
	n.name = "WrensComet"
	Game.main.add_child(n)
	d.track(n)
	n.global_position = from + Vector3(-600.0, 420.0, -1400.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.92, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 6.0
	sm.height = 12.0
	head.mesh = sm
	head.material_override = mat
	n.add_child(head)
	for i in 6:
		var tail := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 5.0 + i * 3.0
		cm.height = 160.0 + i * 50.0
		tail.mesh = cm
		var tm: StandardMaterial3D = mat.duplicate()
		tm.albedo_color.a = 0.22 - i * 0.03
		tail.material_override = tm
		tail.rotation = Vector3(0, 0, deg_to_rad(62.0))
		tail.position = Vector3(cm.height * 0.45, cm.height * 0.23, 0)
		n.add_child(tail)
