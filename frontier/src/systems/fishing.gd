extends Node3D
## Fishing. With a rod in the satchel, press Fish (B / D-pad left) at the water's edge. Hold Fire to wind up the
## cast and release; wait for a nibble (the float bobs) and strike with Fire inside the window; then play the fish:
## hold Fire to reel, ease off when the line sings (tension near the top snaps it, slack lets the hook fall out).
## Landed fish can be kept (sold at the butcher, eaten at camp) or released (a little Standing). Species and size
## depend on the water (river, creek, lake), the hour and the weather.

enum S { IDLE, WINDUP, WAITING, NIBBLE, FIGHT, LANDED }

const SPECIES := {
	"rainbow_trout": {"name": "Rainbow Trout", "water": ["river", "creek"], "lb": [0.5, 6.0], "fight": 1.1, "price": 0.9},
	"brown_trout": {"name": "Brown Trout", "water": ["river"], "lb": [0.8, 9.0], "fight": 1.2, "price": 1.0},
	"brook_trout": {"name": "Brook Trout", "water": ["creek"], "lb": [0.3, 3.0], "fight": 0.9, "price": 0.8},
	"channel_catfish": {"name": "Channel Catfish", "water": ["river", "lake"], "lb": [1.0, 18.0], "fight": 1.4, "price": 0.7},
	"smallmouth_bass": {"name": "Smallmouth Bass", "water": ["river", "lake"], "lb": [0.7, 6.0], "fight": 1.3, "price": 0.8},
	"largemouth_bass": {"name": "Largemouth Bass", "water": ["lake"], "lb": [1.0, 11.0], "fight": 1.3, "price": 0.9},
	"yellow_perch": {"name": "Yellow Perch", "water": ["lake"], "lb": [0.2, 1.5], "fight": 0.6, "price": 0.5},
	"northern_pike": {"name": "Northern Pike", "water": ["lake"], "lb": [2.0, 22.0], "fight": 1.6, "price": 1.1},
}

var state := S.IDLE
var auto := false                  # bots: plays every step itself
var water_kind := ""
var bobber_pos := Vector3.ZERO
var tension := 0.0
var line_len := 0.0
var fish: Dictionary = {}
var catches: Array = []
var _t := 0.0
var _windup := 0.0
var _nibble_at := 0.0
var _slack_t := 0.0
var _rng := RandomNumberGenerator.new()
var _bobber: MeshInstance3D
var _line: MeshInstance3D
var _imesh: ImmediateMesh
var _hud: Control

func _ready() -> void:
	Game.set("fishing", self)
	_rng.randomize()
	if InputMap.has_action("fish") == false:
		InputMap.add_action("fish")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_B
		InputMap.action_add_event("fish", k)
		var j := InputEventJoypadButton.new()
		j.button_index = JOY_BUTTON_DPAD_LEFT
		InputMap.action_add_event("fish", j)
	if not Game.headless:
		_bobber = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.09
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.12, 0.08)
		sm.material = mat
		_bobber.mesh = sm
		_bobber.visible = false
		add_child(_bobber)
		_imesh = ImmediateMesh.new()
		_line = MeshInstance3D.new()
		_line.mesh = _imesh
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(0.85, 0.82, 0.7)
		_line.material_override = lm
		add_child(_line)
		_hud = _make_hud()

## Water within casting reach in front of Ruth, and what kind it is ("" if none).
func water_ahead(p: Node3D) -> String:
	var w: WorldData = Game.world
	var fwd := Vector3(-sin(p.facing), 0, -cos(p.facing))
	for d in [3.0, 6.0, 10.0, 14.0]:
		var q: Vector3 = p.global_position + fwd * d
		if w.is_water(q.x, q.z):
			if q.y <= w.lake_level + 2.0 and absf(w.water_level(q.x, q.z) - w.lake_level) < 0.5:
				return "lake"
			var r = w.river_at(q.x, q.z) if w.has_method("river_at") else {}
			return "river" if typeof(r) == TYPE_DICTIONARY and str(r.get("name", "")) == "Sable River" else ("creek" if typeof(r) == TYPE_DICTIONARY and not r.is_empty() else "river")
	return ""

func can_fish() -> bool:
	return Game.state != null and int(Game.state.inventory.get("fishing_rod", 0)) > 0

func start(p: Node3D) -> bool:
	if state != S.IDLE:
		return false
	if not can_fish():
		Game.say("You'd need a rod. The general store sells them.", 3.0)
		return false
	water_kind = water_ahead(p)
	if water_kind == "":
		Game.say("No water within a cast.", 2.0)
		return false
	state = S.WINDUP
	_windup = 0.0
	p.set("busy", self)
	Game.log_event("fishing_start", {"water": water_kind})
	return true

func stop() -> void:
	state = S.IDLE
	if Game.player:
		Game.player.set("busy", null)
	if _bobber:
		_bobber.visible = false
	if _imesh:
		_imesh.clear_surfaces()
	if _hud:
		_hud.visible = false

func _pick_fish() -> Dictionary:
	var pool: Array = []
	for k in SPECIES.keys():
		if water_kind in SPECIES[k].water:
			pool.append(k)
	var sp: String = pool[_rng.randi() % pool.size()]
	var d: Dictionary = SPECIES[sp]
	var t := pow(_rng.randf(), 2.2)            # most fish are small
	var lb := snappedf(lerpf(d.lb[0], d.lb[1], t), 0.1)
	return {"species": sp, "name": d.name, "lb": lb, "fight": d.fight * (0.7 + t * 0.8), "stamina": 1.0}

## Fish feed at dawn and dusk and under cloud; slower at noon and at night.
func _bite_wait() -> float:
	var h: float = Game.sky.hours if Game.sky else 9.0
	var dawn_dusk := maxf(1.0 - absf(h - 6.5) / 2.5, 1.0 - absf(h - 18.0) / 2.5)
	var cover: float = Game.sky.cover if Game.sky else 0.3
	var rate := 0.6 + clampf(dawn_dusk, 0.0, 1.0) * 0.9 + cover * 0.4
	return _rng.randf_range(4.0, 16.0) / rate

func _physics_process(dt: float) -> void:
	var p = Game.player
	if p == null:
		return
	if state == S.IDLE:
		if not auto and Input.is_action_just_pressed("fish") and p.get("on_horse") == null:
			start(p)
		return
	if not auto and (Input.is_action_just_pressed("fish") or Input.is_action_just_pressed("crouch")):
		stop()
		return
	var fire: bool = Input.is_action_pressed("fire") if not auto else _auto_fire()
	var fire_edge: bool = Input.is_action_just_pressed("fire") if not auto else fire
	_t += dt
	match state:
		S.WINDUP:
			if fire:
				_windup = minf(_windup + dt * 0.8, 1.0)
			elif _windup > 0.05:
				var fwd := Vector3(-sin(p.facing), 0, -cos(p.facing))
				var dist := lerpf(4.0, 18.0, _windup)
				bobber_pos = p.global_position + fwd * dist
				if not Game.world.is_water(bobber_pos.x, bobber_pos.z):
					bobber_pos = p.global_position + fwd * 6.0
				bobber_pos.y = Game.world.water_level(bobber_pos.x, bobber_pos.z)
				line_len = dist
				state = S.WAITING
				_t = 0.0
				_nibble_at = _bite_wait() * (0.15 if auto else 1.0)
				Game.log_event("fishing_cast", {"dist": snappedf(dist, 0.1)})
		S.WAITING:
			if _t >= _nibble_at:
				state = S.NIBBLE
				_t = 0.0
				fish = _pick_fish()
			elif fire_edge and _t > 0.5:
				state = S.WINDUP       # reeled in early: cast again
				_windup = 0.0
		S.NIBBLE:
			if fire_edge:
				state = S.FIGHT
				tension = 0.35
				_slack_t = 0.0
				Game.log_event("fishing_hooked", {"species": fish.species})
			elif _t > 0.7:
				state = S.WAITING        # missed the strike; the fish noses the bait again later
				_t = 0.0
				_nibble_at = _bite_wait()
		S.FIGHT:
			_fight(dt, fire)
		S.LANDED:
			pass
	_draw(p)

func _fight(dt: float, reeling: bool) -> void:
	# the fish runs in bursts; reeling against a run spikes the tension
	var run: float = maxf(0.0, sin(_t * (1.3 + fish.fight)) + _rng.randf_range(-0.3, 0.3)) * fish.fight * fish.stamina
	if reeling:
		tension += (0.35 + run * 0.9) * dt
		line_len = maxf(line_len - (1.6 - run * 0.8) * dt * 2.0, 0.0)
	else:
		tension -= (0.45 - run * 0.25) * dt
		line_len += run * dt * 2.5
	tension = clampf(tension, 0.0, 1.2)
	fish.stamina = maxf(fish.stamina - dt * (0.05 + (0.08 if tension > 0.5 else 0.0)), 0.15)
	if tension >= 1.0:
		Game.say("The line parts with a crack. Gone.", 2.5)
		Game.log_event("fishing_lost", {"why": "snapped"})
		stop()
		return
	_slack_t = _slack_t + dt if tension < 0.08 else 0.0
	if _slack_t > 2.0:
		Game.say("Slack line — the hook falls out.", 2.5)
		Game.log_event("fishing_lost", {"why": "slack"})
		stop()
		return
	if line_len <= 0.5:
		_land()

func _land() -> void:
	state = S.LANDED
	catches.append(fish.duplicate())
	Game.log_event("fishing_landed", {"species": fish.species, "lb": fish.lb})
	var menus = Game.get("menus")
	if auto or menus == null or Game.headless:
		keep()
		return
	var pnl: PanelContainer = menus._paper_panel(Vector2(620, 300))
	var v := VBoxContainer.new()
	pnl.add_child(v)
	v.add_child(UITheme.label("%s, %.1f lb" % [fish.name, fish.lb], 40, "display", UITheme.INK, false))
	v.add_child(menus._button("Keep it", func():
		menus.back()
		keep()))
	v.add_child(menus._button("Let it go", func():
		menus.back()
		release()))
	menus._push(pnl)

func keep() -> void:
	Game.state.add_item("fish_%s" % fish.species)
	Game.say("%s, %.1f lb. Into the creel." % [fish.name, fish.lb], 3.0)
	stop()

func release() -> void:
	Game.state.change_standing(0.2, "released a fish")
	Game.say("You slip the %s back into the water." % fish.name.to_lower(), 3.0)
	stop()

## Value at the butcher for one fish of a species (dollars, before Standing pricing).
static func price(species: String) -> float:
	return float(SPECIES.get(species, {}).get("price", 0.5))

# ------------------------------------------------------------------ bot play
func _auto_fire() -> bool:
	match state:
		S.WINDUP: return _windup < 0.6
		S.WAITING: return false
		S.NIBBLE: return true
		S.FIGHT: return tension < 0.7
	return false

# ------------------------------------------------------------------ visuals
func _draw(p: Node3D) -> void:
	if Game.headless or _bobber == null:
		return
	var bob := state in [S.WAITING, S.NIBBLE, S.FIGHT]
	_bobber.visible = bob
	var bp := bobber_pos
	if state == S.NIBBLE:
		bp.y -= 0.04 + 0.03 * sin(_t * 30.0)
	elif state == S.FIGHT:
		var toward: Vector3 = (p.global_position - bobber_pos)
		toward.y = 0.0
		bp = p.global_position - toward.normalized() * line_len
		bp.y = Game.world.water_level(bp.x, bp.z) - 0.05 * tension
		bp += Vector3(sin(_t * 2.3), 0, cos(_t * 1.7)) * 0.6 * fish.get("fight", 1.0)
	else:
		bp.y += 0.01 * sin(_t * 2.0)
	_bobber.global_position = bp
	_imesh.clear_surfaces()
	if bob:
		var tip: Vector3 = p.global_position + Vector3(-sin(p.facing), 0, -cos(p.facing)) * 1.6 + Vector3(0, 2.2, 0)
		_imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var sag := 0.6 * (1.0 - tension)
		for i in 13:
			var f := i / 12.0
			var q := tip.lerp(bp, f)
			q.y -= sin(f * PI) * sag
			_imesh.surface_add_vertex(q)
		_imesh.surface_end()
	if _hud:
		_hud.visible = state != S.IDLE
		_hud.queue_redraw()

func _make_hud() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	c.draw.connect(func():
		var sz := c.get_viewport_rect().size
		var x := sz.x * 0.5 - 160.0
		var y := sz.y - 150.0
		var txt := ""
		match state:
			S.WINDUP: txt = "Hold Fire to wind up, release to cast"
			S.WAITING: txt = "Waiting for a bite…"
			S.NIBBLE: txt = "Strike! (Fire)"
			S.FIGHT: txt = "Reel (hold Fire) — ease off when the line sings"
		c.draw_string(UITheme.font("body"), Vector2(x, y - 12.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UITheme.PAPER)
		var v := _windup if state == S.WINDUP else tension
		if state in [S.WINDUP, S.FIGHT]:
			c.draw_rect(Rect2(x, y, 320, 14), Color(0, 0, 0, 0.45))
			var col := UITheme.PAPER if v < 0.75 else Color(0.8, 0.25, 0.15)
			c.draw_rect(Rect2(x, y, 320 * clampf(v, 0.0, 1.0), 14), col)
	)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(c)
	return c
