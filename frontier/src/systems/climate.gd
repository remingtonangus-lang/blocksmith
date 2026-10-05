extends Node
## Temperature and clothing. The air temperature at a place and hour comes from the season on the story's calendar
## (autumn 1899, the winter, spring 1900), the altitude (6.5 °C colder per 1000 m above the lake — the Kestrel and
## the snow line are cold), the hour (cold nights, warm afternoons), the weather (rain and storms chill) and the
## south (the Ocotillo country bakes by day). What Ruth wears decides how it feels: her own clothes are warmth 2;
## the outfits made from legendary pelts carry their own warmth (a bearskin coat is warm, the Pale Ghost vest is
## light and keeps the sun off). Too cold and her breath fogs, then stamina and health drain; too hot in a heavy
## coat and stamina drains. A small HUD gauge says so in degrees Fahrenheit. The camp fire and the mission cold
## system (cold_begin) take precedence.

const NEWS = preload("res://src/systems/newspaper.gd")
const LAKE := 120.0
## Warmth of what she wears: [warmth, heat_shade] (shade cancels some of the sun's heat).
const WARMTH := {"": [2.0, 0.0], "grey_widow": [4.0, 0.0], "ironhide": [5.0, 0.0], "pale_ghost": [2.5, 4.0], "sable_king": [3.0, 1.0]}
const SEASON_BASE := {1: 15.0, 2: 13.0, 3: 12.0, 4: 2.0, 5: -1.0, 6: 1.0, 7: 14.0}

var temp_c := 15.0
var feel_c := 15.0
var cold := 0.0                 # 0..1 how badly
var heat := 0.0
var breath_on := false
var _breath: CPUParticles3D = null
var _gauge: Label = null
var _t := 0.0
var _warned := ""

func _ready() -> void:
	Game.set_meta("climate", self)
	if not Game.headless:
		var cl := CanvasLayer.new()
		cl.layer = 6
		add_child(cl)
		_gauge = Label.new()
		_gauge.add_theme_font_override("font", UITheme.font("caps"))
		_gauge.add_theme_font_size_override("font_size", 22)
		_gauge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		_gauge.anchor_left = 1.0
		_gauge.anchor_right = 1.0
		_gauge.offset_left = -330
		_gauge.offset_right = -24
		_gauge.offset_top = 150
		_gauge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.add_child(_gauge)

## Air temperature (°C) at a point, hour, weather and chapter (pure; bots test it).
static func temperature(pos: Vector3, hour: float, weather: String, chapter: int) -> float:
	var t: float = SEASON_BASE.get(chapter, 12.0)
	t -= maxf(pos.y - LAKE, 0.0) * 0.0065
	var day := cos((hour - 15.0) / 24.0 * TAU)          # +1 at 3 p.m., -1 at 3 a.m.
	t += day * 7.0
	var south := clampf((pos.z - 800.0) / 1200.0, 0.0, 1.0)
	t += south * (15.0 if day > 0.0 else 3.0) * maxf(day, 0.2)
	match weather:
		"RAIN": t -= 4.0
		"STORM": t -= 6.0
		"FOG": t -= 2.0
		"OVERCAST": t -= 1.0
	return t

## How it feels in what she wears: [feel °C for cold, feel °C for heat].
static func feels(temp: float, outfit: String) -> Array:
	var w: Array = WARMTH.get(outfit, WARMTH[""])
	var cold_feel := temp + (float(w[0]) - 2.0) * 4.0
	var heat_feel := temp + (float(w[0]) - 2.0) * 3.0 - float(w[1])
	return [cold_feel, heat_feel]

static func cold_strength(cold_feel: float) -> float:
	return clampf((2.0 - cold_feel) / 10.0, 0.0, 1.0)

static func heat_strength(heat_feel: float) -> float:
	return clampf((heat_feel - 35.0) / 8.0, 0.0, 1.0)

func _outfit() -> String:
	return str(Game.state.flags.get("outfit_worn", "")) if Game.state else ""

func _sheltered(p: Node3D) -> bool:
	var camp = Game.get("camp")
	if camp != null and camp.get("center") != null and p.global_position.distance_to(camp.center) < 7.0:
		return true                   # the fire
	var md = Game.missions
	return md != null and float(md.get("cold_rate")) > 0.0     # a mission's own cold

func _process(dt: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p) or Game.sky == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 1.0
		var done: Array = Game.missions.completed if Game.missions else []
		temp_c = temperature(p.global_position, float(Game.sky.hours), str(SkySystem.Weather.keys()[Game.sky.weather]), NEWS.story_chapter(done))
		var f := feels(temp_c, _outfit())
		feel_c = float(f[0])
		var sheltered := _sheltered(p)
		cold = 0.0 if sheltered else cold_strength(float(f[0]))
		heat = 0.0 if sheltered else heat_strength(float(f[1]))
		_breath_fx(p, temp_c < 4.0)
		_hud()
	# the drain: stamina first, then health (never below a fifth from weather alone)
	if cold > 0.0 or heat > 0.0:
		var s := maxf(cold, heat)
		if p.get("stamina") != null:
			# outruns her breathing back: the ceiling sinks to 40% at the worst and the reserve bleeds toward it
			var cap: float = float(p.STAMINA_MAX) * (1.0 - 0.6 * s)
			var st_now: float = float(p.stamina)
			if st_now > cap:
				st_now = maxf(st_now - (12.0 + s * 10.0) * dt, cap)
			p.stamina = st_now
		if cold > 0.25 and p.damageable and p.damageable.health > p.damageable.max_health * 0.2:
			p.damageable.set("_since_hit", 0.0)          # the cold keeps her from mending
			p.damageable.health = maxf(p.damageable.health - cold * 0.8 * dt, p.damageable.max_health * 0.2)
			p.health = p.damageable.health

func _breath_fx(p: Node3D, on: bool) -> void:
	breath_on = on
	if Game.headless:
		return
	if on and (_breath == null or not is_instance_valid(_breath)):
		_breath = CPUParticles3D.new()
		_breath.name = "BreathFog"
		_breath.amount = 10
		_breath.lifetime = 1.4
		_breath.explosiveness = 0.75
		_breath.direction = Vector3(0, 0.2, -1)
		_breath.spread = 18.0
		_breath.initial_velocity_min = 0.25
		_breath.initial_velocity_max = 0.5
		_breath.gravity = Vector3(0, 0.08, 0)
		_breath.scale_amount_min = 0.06
		_breath.scale_amount_max = 0.16
		var q := QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(0.95, 0.96, 1.0, 0.28)
		q.material = m
		_breath.mesh = q
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.5))
		g.set_color(1, Color(1, 1, 1, 0.0))
		_breath.color_ramp = g
		p.add_child(_breath)
		_breath.position = Vector3(0, 1.6, -0.22)
	if _breath and is_instance_valid(_breath):
		_breath.emitting = on
		_breath.rotation.y = 0.0
		if p.get("visual") != null:
			_breath.rotation.y = p.visual.rotation.y

func _hud() -> void:
	var f := temp_c * 9.0 / 5.0 + 32.0
	var word := ""
	if cold > 0.0:
		word = "cold" if cold < 0.5 else "freezing"
	elif heat > 0.0:
		word = "hot" if heat < 0.5 else "sweltering"
	if _gauge:
		_gauge.text = ("%d°F — %s" % [int(round(f)), word]) if word != "" else ""
		_gauge.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0) if cold > 0.0 else Color(1.0, 0.72, 0.45))
	if word != "" and word != _warned:
		_warned = word
		Game.log_event("climate", {"temp_c": snappedf(temp_c, 0.1), "state": word, "outfit": _outfit()})
		if Game.hud and not Game.headless:
			Game.hud.notice("You're %s. %s" % [word, "Get to a fire or put on something warmer." if cold > 0.0 else "Shed the heavy coat or find shade."], 4.0)
	elif word == "":
		_warned = ""
