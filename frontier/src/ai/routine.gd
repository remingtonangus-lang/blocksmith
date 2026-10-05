class_name TownRoutine
extends RefCounted
## One resident's day, driven by brain.gd while it is in ROUTINE: asks TownSchedule for the current block, claims an
## interaction spot for it (population.gd keeps the claims), walks there on the town navmesh (doors open on the way,
## see Human._town_tick), settles onto the spot (Human.anchor_to: seats, counters, the bar rail) with the matching
## activity loop and sit_down/stand_up gestures, dwells with small gestures, and moves on when the block changes or
## the dwell runs out. Strollers who meet stop to chat (talk_1/talk_2 facing each other). Interrupted by brain.gd
## for reactions (flee, cower, hold-ups); resume() picks the day up again.
##
## Phases: plan -> walk -> at (anchored on a spot, or standing at a point) -> leave -> plan; chat pauses a walk;
## "home" ends with the resident going indoors (population despawns them until the schedule brings them out).

var body: Human
var res: Dictionary
var pop: Node
var rng := RandomNumberGenerator.new()
var block := {}
var phase := "plan"
var spot := {}                 # claimed spot (settlement spot or synthetic street spot), {} for a plain point
var goal := Vector3.INF
var task := ""                 # what the current walk is for: spot, point, home
var t := 0.0
var dwell := 0.0
var walk_limit := 0.0
var act_t := 0.0
var check_t := 0.0
var seated := false
var activity := ""
var partner: Human = null
var chat_cool := 0.0
var fails := 0
var patrol_i := -1
var leave_t := 0.0
var wait_t := 0.0
var last_type := ""            # spot type of the last place (diagnostics)

func _init(b: Human, r: Dictionary, p: Node) -> void:
	body = b
	res = r
	pop = p
	rng.seed = int(r.get("seed", 1)) + Time.get_ticks_msec()
	chat_cool = rng.randf_range(10.0, 40.0)
	patrol_i = -1

func busy_seated() -> bool:
	return phase == "at" and seated

## Called every physics frame by brain._routine.
func tick(dt: float) -> void:
	t += dt
	chat_cool -= dt
	check_t -= dt
	if check_t <= 0.0:
		check_t = 2.0 + rng.randf()
		var b: Dictionary = pop.block_for(res)
		if b.key != block.get("key", ""):
			block = b
			if phase in ["at", "chat"]:
				_leave()
			elif phase == "walk":
				_release()
				phase = "plan"
	match phase:
		"plan":
			_plan(dt)
		"walk":
			_walk(dt)
		"at":
			_at(dt)
		"leave":
			body.intent.move_to = null
			if t >= leave_t:
				body.release_anchor()
				phase = "plan"
				t = 0.0
		"chat":
			_chat(dt)

## Arrive on a spot at once (spawning mid-day: people are already where the hour puts them).
func place_now() -> bool:
	block = pop.block_for(res)
	if block.kind == "home":
		return false
	if not _choose():
		return false
	if task == "spot" or task == "point":
		body.global_position = goal
		_arrive(true)
		return true
	return false

func interrupt() -> void:
	_release()
	if partner != null and is_instance_valid(partner) and partner.brain.get("routine") != null:
		var pr: TownRoutine = partner.brain.routine
		if pr.partner == body:
			pr._end_chat()
	partner = null
	if body.anchored:
		body.release_anchor()
	_set_activity("")
	phase = "plan"
	t = 0.0

func resume() -> void:
	check_t = 0.0
	block = {}
	phase = "plan"

# ------------------------------------------------------------------ phases

func _plan(dt: float) -> void:
	body.intent.move_to = null
	wait_t -= dt
	if wait_t > 0.0:
		return
	if block.is_empty():
		block = pop.block_for(res)
	if not pop.nav_ready(res.town):
		# no navmesh yet: hold still (or vanish home unseen) rather than walking into walls
		if block.kind == "home" and pop.unseen(body, 60.0):
			pop.went_home(self)
		wait_t = 1.0
		return
	if not _choose():
		wait_t = rng.randf_range(2.0, 5.0)
		return
	phase = "walk"
	t = 0.0
	var d := Vector2(goal.x - body.global_position.x, goal.z - body.global_position.z).length()
	walk_limit = d / _speed() * 2.2 + 25.0
	pop.stat("trips", 1)
	# out of sight and far from Ruth: skip the walk (keeps distant towns cheap and on schedule)
	if d > 8.0 and pop.unseen(body, 150.0) and pop.unseen_point(goal, 150.0):
		body.global_position = goal + Vector3(0, 0.05, 0)
		pop.stat("skipped", 1)
		_arrive(true)

## Pick the next task for the block: sets spot/goal/task. False when nothing fits right now.
func _choose() -> bool:
	spot = {}
	task = ""
	var k: String = block.kind
	var bid: String = block.get("bid", "")
	match k:
		"home":
			var hs: Dictionary = pop.home_spot(res)
			if hs.is_empty():
				return false
			goal = hs.transform.origin
			task = "home"
			return true
		"work":
			spot = pop.claim(self, res.work, block.types)
			if spot.is_empty():
				spot = pop.claim(self, res.work, ["work", "chair", "bench"])
		"errands":
			var shop: String = pop.open_shop(res, rng)
			if shop != "":
				spot = pop.claim(self, shop, TownSchedule.CUSTOMER.get(pop.btype(shop), ["shop_counter"]))
			if spot.is_empty():
				spot = pop.claim_street(self)
		"loiter":
			# sometimes walk over to someone idling on the street and stop for a talk
			if rng.randf() < 0.35:
				var o: Human = pop.idler_to_join(body)
				if o != null:
					var ofw := Vector3(-sin(o.facing), 0.0, -cos(o.facing))
					var g: Vector3 = pop.snap(o.global_position + ofw * 1.1)
					if g != Vector3.INF and g.distance_to(o.global_position) < 1.6:
						goal = g
						partner = o
						task = "join"
						return true
			spot = pop.claim_street(self)
		"porch":
			if bid != "":
				spot = pop.claim(self, bid, ["porch_sit"])
			if spot.is_empty():
				spot = pop.claim_street(self)
		"bar":
			spot = pop.claim(self, bid, ["bar_patron"])
			if spot.is_empty():
				spot = pop.claim(self, bid, ["chair"], "table")
		"tables":
			spot = pop.claim(self, bid, ["chair"], "table")
			if spot.is_empty():
				spot = pop.claim(self, bid, ["bar_patron"])
		"cards":
			spot = pop.claim(self, bid, ["chair"], "cards")
			if spot.is_empty():
				spot = pop.claim(self, bid, ["chair"], "table")
		"piano":
			spot = pop.claim(self, bid, ["piano"])
		"eat":
			spot = pop.claim(self, bid, ["chair"])
		"church":
			spot = pop.claim(self, bid, ["bench"])
		"school":
			spot = pop.claim(self, bid, ["bench"])
		"play", "stagger":
			var c: Vector3 = pop.yard(res.town) if k == "play" else pop.saloon_front(res.town)
			if c == Vector3.INF:
				return false
			var p := c + Vector3(rng.randf_range(-9.0, 9.0), 0.0, rng.randf_range(-9.0, 9.0))
			goal = pop.snap(p)
			task = "point"
			return goal != Vector3.INF
		"patrol":
			var pts: Array = pop.patrol_points(res.town)
			if pts.is_empty():
				return false
			if patrol_i < 0:
				patrol_i = _nearest_index(pts)
			patrol_i = (patrol_i + 1) % pts.size()
			goal = pts[patrol_i]
			task = "point"
			return true
	if spot.is_empty():
		return false
	goal = spot.transform.origin
	task = "spot"
	return true

func _nearest_index(pts: Array) -> int:
	var best := 0
	var bd := INF
	for i in pts.size():
		var d: float = (pts[i] as Vector3).distance_squared_to(body.global_position)
		if d < bd:
			bd = d
			best = i
	return best

func _speed() -> float:
	match block.get("kind", ""):
		"stagger":
			return 0.62
		"play":
			return 2.6 if rng.randf() < 0.5 else Human.WALK
		"patrol":
			return 1.25
	return Human.WALK * (0.85 if res.kind in ["elder", "matron"] else 1.0)

func _walk(_dt: float) -> void:
	body.intent.move_to = goal
	body.intent.face = null
	var k: String = block.get("kind", "")
	if body.intent.speed <= 0.1 or t < 0.05:
		body.intent.speed = _speed()
	if k == "stagger" and activity != "walk_wounded":
		_set_activity("walk_wounded")
	var to := goal - body.global_position
	if task == "join" and (partner == null or not is_instance_valid(partner) or partner.brain.routine == null or partner.brain.routine.phase != "at"):
		partner = null
		phase = "plan"
		return
	var near := 0.5 if task == "spot" else 1.0
	if task == "home":
		near = 0.7
	var flat := Vector2(to.x, to.z).length()
	var done: bool = t > 1.0 and body.path_done()
	if (flat < near or (done and flat < 1.2 and task != "point")) and absf(to.y) < 1.3:
		pop.stat("reached", 1)
		_arrive(false)
		return
	if done and flat >= 1.2 and task == "spot":
		# the navmesh can't get closer than this: that spot is out of reach (behind a counter, in a stall)
		spot["bad"] = true
		pop.stat("unreachable", 1)
		_release()
		phase = "plan"
		wait_t = 0.5
		return
	if t > walk_limit:
		pop.stat("failed", 1)
		fails += 1
		if pop.unseen(body, 40.0):
			body.global_position = goal + Vector3(0, 0.05, 0)
			_arrive(true)
			return
		_release()
		phase = "plan"
		wait_t = 1.0
		if fails >= 2:
			block = {"key": "loiter|", "kind": "loiter", "bid": "", "types": []}
		return
	# strollers who meet stop for a word
	if chat_cool <= 0.0 and k in ["errands", "loiter", "porch"] and int(t * 4.0) % 4 == 0:
		chat_cool = 3.0
		var o: Human = pop.near_walker(body, 2.6)
		if o != null and rng.randf() < 0.55:
			_start_chat(o)
			var pr: TownRoutine = o.brain.routine
			pr._start_chat(body)

func _arrive(instant: bool) -> void:
	phase = "at"
	t = 0.0
	act_t = rng.randf_range(4.0, 10.0)
	body.intent.move_to = null
	if task == "home":
		pop.went_home(self)
		return
	var k: String = block.get("kind", "")
	if task == "join" and partner != null and is_instance_valid(partner):
		var o := partner
		partner = null
		_start_chat(o)
		dwell = rng.randf_range(15.0, 35.0)
		var pr: TownRoutine = o.brain.routine
		o.intent.face = body.global_position - o.global_position
		if pr != null:
			pr.partner = body
			pr._set_activity(["talk_1", "talk_2"][rng.randi() % 2])
			pr.t = minf(pr.t, pr.dwell - dwell)       # the one being visited stays for the talk
			if o.visual.has_method("look_at_node"):
				o.visual.look_at_node(body, 0.6)
		return
	if task == "spot":
		body.anchor_to(spot.transform, 0.0 if instant else 0.45)
		seated = spot.has("sit_height") and str(spot.type) != "bath"
		var act := TownSchedule.activity_for(spot, k, rng)
		_set_activity(act)
		if seated and not instant and body.visual.has_method("gesture"):
			body.visual.gesture("sit_down")
	else:
		seated = false
		_set_activity("" if k != "stagger" else "idle_shift")
	match k:
		"work":
			dwell = rng.randf_range(70.0, 170.0)
		"errands":
			dwell = rng.randf_range(25.0, 60.0)
		"loiter", "porch":
			dwell = rng.randf_range(40.0, 120.0)
		"play":
			dwell = rng.randf_range(2.0, 7.0)
		"stagger":
			dwell = rng.randf_range(4.0, 14.0)
		"patrol":
			dwell = rng.randf_range(4.0, 9.0)
		_:
			dwell = rng.randf_range(150.0, 400.0)
	if instant and task == "spot":
		t = rng.randf_range(0.0, dwell * 0.85)      # placed mid-visit: departures are staggered from the start

func _at(dt: float) -> void:
	act_t -= dt
	if act_t <= 0.0:
		act_t = rng.randf_range(6.0, 14.0)
		_micro()
	if t > dwell:
		_leave()

## Small life while dwelling: gestures, swapping the activity loop, looking at a neighbour.
func _micro() -> void:
	var v = body.visual
	if not v.has_method("gesture"):
		return
	var k: String = block.get("kind", "")
	if task == "point":
		if k == "patrol":
			body.intent.face = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		return
	var n: Human = pop.neighbour(body, 2.2)
	if seated:
		if n != null and v.has_method("look_at_node"):
			v.look_at_node(n, 0.5)
		elif v.has_method("clear_look"):
			v.clear_look()
		return
	var st: String = spot.get("type", "")
	if st == "bar_patron":
		var a: String = ["drink", "drink_smoke", "talk_1", "idle_wait"][rng.randi() % 4]
		if a == "talk_1" and n == null:
			a = "drink"
		_set_activity(a)
		if a == "talk_1" and v.has_method("look_at_node"):
			v.look_at_node(n, 0.5)
		return
	if n != null and rng.randf() < 0.4:
		if v.has_method("look_at_node"):
			v.look_at_node(n, 0.5)
		_set_activity(["talk_1", "talk_2"][rng.randi() % 2])
		return
	var g: Array = TownSchedule.gestures_for(spot)
	if not g.is_empty() and rng.randf() < 0.45:
		v.gesture(g[rng.randi() % g.size()])
	elif rng.randf() < 0.3:
		_set_activity(TownSchedule.activity_for(spot, k, rng))

func _leave() -> void:
	_release()
	if partner != null:
		_end_chat()
	var v = body.visual
	if v.has_method("clear_look"):
		v.clear_look()
	if seated and body.anchored and v.has_method("gesture"):
		v.gesture("stand_up")
		leave_t = 1.7
	else:
		leave_t = 0.15
	_set_activity("")
	seated = false
	phase = "leave"
	t = 0.0

func _release() -> void:
	if not spot.is_empty():
		last_type = str(spot.get("type", ""))
		pop.release(spot, body)
	spot = {}

# ------------------------------------------------------------------ chatting

func _start_chat(o: Human) -> void:
	partner = o
	phase = "chat"
	t = 0.0
	dwell = rng.randf_range(8.0, 18.0)
	act_t = rng.randf_range(2.0, 5.0)
	body.intent.move_to = null
	_set_activity(["talk_1", "talk_2"][rng.randi() % 2])
	if body.visual.has_method("look_at_node"):
		body.visual.look_at_node(o, 0.6)
	pop.stat("chats", 1)

func _chat(dt: float) -> void:
	body.intent.move_to = null
	if partner == null or not is_instance_valid(partner) or not partner.alive or t > dwell:
		_end_chat()
		return
	body.intent.face = partner.global_position - body.global_position
	act_t -= dt
	if act_t <= 0.0:
		act_t = rng.randf_range(3.0, 7.0)
		if body.visual.has_method("gesture") and rng.randf() < 0.5:
			body.visual.gesture(["shrug", "talk_directions"][rng.randi() % 2])

func _end_chat() -> void:
	var p := partner
	partner = null
	chat_cool = rng.randf_range(50.0, 120.0)
	body.intent.face = null
	_set_activity("")
	if body.visual.has_method("clear_look"):
		body.visual.clear_look()
	if phase == "chat":
		phase = "walk" if goal != Vector3.INF and task != "" else "plan"
		t = 0.0
	if p != null and is_instance_valid(p) and p.brain.get("routine") != null:
		var pr: TownRoutine = p.brain.routine
		if pr.partner == body:
			pr._end_chat()

func _set_activity(a: String) -> void:
	activity = a
	if body.visual.has_method("set_activity"):
		body.visual.set_activity(a)
