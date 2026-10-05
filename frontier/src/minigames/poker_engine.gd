extends RefCounted
## Five-card draw, the way it was played across a saloon table in 1899: everybody antes, five cards each, a betting
## round, one draw (up to three cards, four if you keep an ace), a second betting round at double the limit, then
## the showdown. Fixed limit, three raises a round, side pots for anybody all-in. Pure logic and deterministic for a
## seed: shared by the table (poker.gd), the mission autopilot and the --pokertest self-test.
##
## Money is in cents. Cards are ints 0..51: rank = c % 13 (0 = deuce .. 12 = ace), suit = c / 13
## (0 spades, 1 hearts, 2 diamonds, 3 clubs). Hand scores are ints that compare directly (higher wins):
## category << 20 | five 4-bit tiebreak ranks.
##
## A stacked ("rigged") hand: the house dealer gives the plant three of a rank and the mark a pat flush, then deals
## the plant his fourth card from the bottom of the deck on the draw. The table narrates it through `events`
## ("tell_deal", "tell_draw") so a sharp player can catch it.

const RANKS := "23456789TJQKA"
const SUITS := "shdc"
const RANK_LABEL := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const RANK_NAME := ["deuce", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king", "ace"]
const RANK_PLURAL := ["deuces", "threes", "fours", "fives", "sixes", "sevens", "eights", "nines", "tens", "jacks", "queens",
	"kings", "aces"]
const CATEGORY := ["high card", "one pair", "two pair", "three of a kind", "straight", "flush", "full house",
	"four of a kind", "straight flush"]
## Play styles: loose = how many hands it plays, aggro = how often it bets its strength, bluff = how often it bets
## nothing, call_down = how stubbornly it calls after the draw.
const STYLES := {
	"tight": {"loose": 0.12, "aggro": 0.35, "bluff": 0.02, "call_down": 0.30},
	"loose": {"loose": 0.80, "aggro": 0.25, "bluff": 0.06, "call_down": 0.85},
	"bluffer": {"loose": 0.50, "aggro": 0.75, "bluff": 0.32, "call_down": 0.45},
	"plant": {"loose": 0.45, "aggro": 0.40, "bluff": 0.05, "call_down": 0.50},
	"steady": {"loose": 0.35, "aggro": 0.50, "bluff": 0.06, "call_down": 0.50},
}

var rng := RandomNumberGenerator.new()
var seats: Array = []        # {name, style, stack, hand, folded, out, bet, in_pot, all_in, player, drew, last}
var deck: Array = []
var button := 0
var hand_no := 0
var phase := "idle"          # idle, bet1, draw, bet2, done
var to_act := -1
var current_bet := 0
var raises := 0
var pending := {}            # seats that still owe an action this round
var ante := 25
var small_bet := 50
var big_bet := 100
var cap := 3
var rig_hands: Array = []    # hand numbers the dealer stacks
var plant := -1
var mark := -1
var rigged := false
var events: Array = []       # [{kind, seat, text}] for narration; the caller drains it
var last_result := {}
var actions_taken := 0

# ------------------------------------------------------------------ cards and hands
static func rank(c: int) -> int:
	return c % 13

static func suit(c: int) -> int:
	return c / 13

static func card(r: int, s: int) -> int:
	return s * 13 + r

## "Ah" -> ace of hearts, "Ts" -> ten of spades, "10d" -> ten of diamonds.
static func parse(s: String) -> int:
	var t := s.strip_edges().replace("10", "T")
	return card(RANKS.find(t[0].to_upper()), SUITS.find(t[1].to_lower()))

static func parse_hand(s: String) -> Array:
	var out := []
	for t in s.split(" ", false):
		out.append(parse(t))
	return out

static func card_text(c: int) -> String:
	return RANK_LABEL[rank(c)] + ["♠", "♥", "♦", "♣"][suit(c)]

## Score exactly five cards.
static func eval5(cards: Array) -> int:
	var counts := {}
	var flush := true
	var s0 := suit(cards[0])
	for c in cards:
		var r := rank(c)
		counts[r] = int(counts.get(r, 0)) + 1
		if suit(c) != s0:
			flush = false
	var groups := []
	for r in counts.keys():
		groups.append([counts[r], r])
	groups.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var straight_top := -1
	if groups.size() == 5:
		if groups[0][1] - groups[4][1] == 4:
			straight_top = groups[0][1]
		elif groups[0][1] == 12 and groups[1][1] == 3:
			straight_top = 3          # the wheel, ace to five: a five-high straight
	var cat := 0
	if straight_top >= 0 and flush:
		cat = 8
	elif groups[0][0] == 4:
		cat = 7
	elif groups[0][0] == 3 and groups[1][0] == 2:
		cat = 6
	elif flush:
		cat = 5
	elif straight_top >= 0:
		cat = 4
	elif groups[0][0] == 3:
		cat = 3
	elif groups[0][0] == 2 and groups[1][0] == 2:
		cat = 2
	elif groups[0][0] == 2:
		cat = 1
	var ranks := []
	if straight_top >= 0:
		ranks = [straight_top]
	else:
		for g in groups:
			ranks.append(g[1])
	var score := cat
	for i in 5:
		score = score * 16 + (int(ranks[i]) if i < ranks.size() else 0)
	return score

## Best five-card score from any number (>= 5) of cards.
static func best_of(cards: Array) -> int:
	if cards.size() == 5:
		return eval5(cards)
	var best := -1
	var n := cards.size()
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				for d in range(c + 1, n):
					for e in range(d + 1, n):
						best = maxi(best, eval5([cards[a], cards[b], cards[c], cards[d], cards[e]]))
	return best

static func category(score: int) -> int:
	return score >> 20

static func _tb(score: int, i: int) -> int:
	return (score >> (16 - 4 * i)) & 15

## A hand the way a player at the table would say it: "a pair of jacks", "kings over fives", "a flush, ace high".
static func hand_name(score: int) -> String:
	var r0 := _tb(score, 0)
	var r1 := _tb(score, 1)
	match category(score):
		8:
			return "a royal flush" if r0 == 12 else "a straight flush to the %s" % RANK_NAME[r0]
		7:
			return "four %s" % RANK_PLURAL[r0]
		6:
			return "a full house, %s over %s" % [RANK_PLURAL[r0], RANK_PLURAL[r1]]
		5:
			return "a flush, %s high" % RANK_NAME[r0]
		4:
			return "a straight to the %s" % RANK_NAME[r0]
		3:
			return "three %s" % RANK_PLURAL[r0]
		2:
			return "two pair, %s and %s" % [RANK_PLURAL[r0], RANK_PLURAL[r1]]
		1:
			return "a pair of %s" % RANK_PLURAL[r0]
	return "%s high" % RANK_NAME[r0]

# ------------------------------------------------------------------ table
## players: [{name, style, stack (cents), player (bool)}]. opts: rig_hands, plant, mark, ante, small_bet, big_bet.
func setup(players: Array, seed_value: int, opts: Dictionary = {}) -> void:
	rng.seed = seed_value
	seats.clear()
	for p in players:
		seats.append({"name": str(p.get("name", "Stranger")), "style": str(p.get("style", "steady")),
			"stack": int(p.get("stack", 1000)), "hand": [], "folded": false, "out": int(p.get("stack", 1000)) <= 0,
			"bet": 0, "in_pot": 0, "all_in": false, "player": bool(p.get("player", false)), "drew": -1, "last": ""})
	ante = int(opts.get("ante", ante))
	small_bet = int(opts.get("small_bet", small_bet))
	big_bet = int(opts.get("big_bet", big_bet))
	rig_hands = opts.get("rig_hands", [])
	plant = int(opts.get("plant", -1))
	mark = int(opts.get("mark", -1))
	button = int(opts.get("button", 0))
	hand_no = 0
	phase = "idle"

func pot() -> int:
	var t := 0
	for s in seats:
		t += int(s.in_pot)
	return t

func total_chips() -> int:
	var t := pot()
	for s in seats:
		t += int(s.stack)
	return t

func live() -> Array:
	var out := []
	for i in seats.size():
		if not seats[i].out and not seats[i].folded:
			out.append(i)
	return out

func seated() -> Array:
	var out := []
	for i in seats.size():
		if not seats[i].out:
			out.append(i)
	return out

func _next_seat(from: int, pred: Callable) -> int:
	for k in range(1, seats.size() + 1):
		var i := (from + k) % seats.size()
		if pred.call(i):
			return i
	return -1

func _ev(kind: String, seat: int, text := "") -> void:
	events.append({"kind": kind, "seat": seat, "text": text})

func _shuffle() -> void:
	deck = []
	for c in 52:
		deck.append(c)
	for i in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var t = deck[i]
		deck[i] = deck[j]
		deck[j] = t

## Deal a new hand. Returns false when fewer than two players have money left.
func start_hand() -> bool:
	for s in seats:
		if int(s.stack) <= 0:
			s.out = true
	if seated().size() < 2:
		phase = "done"
		return false
	hand_no += 1
	button = _next_seat(button, func(i): return not seats[i].out)
	for s in seats:
		s.hand = []
		s.folded = s.out
		s.bet = 0
		s.in_pot = 0
		s.all_in = false
		s.drew = -1
		s.last = ""
	last_result = {}
	_shuffle()
	var m := mark
	if m < 0 or m >= seats.size() or seats[m].out or m == plant:
		m = -1
		for i in seated():
			if i != plant and (m < 0 or seats[i].stack > seats[m].stack):
				m = i
	rigged = rig_hands.has(hand_no) and plant >= 0 and plant < seats.size() and not seats[plant].out and m >= 0
	for i in seated():
		_put(i, ante)
	if rigged:
		_deal_stacked(m)
		_ev("tell_deal", plant)
	else:
		for _r in 5:
			var i := button
			for _k in seats.size():
				i = (i + 1) % seats.size()
				if not seats[i].out:
					seats[i].hand.append(deck.pop_back())
		if rng.randf() < 0.55:
			_ev("flavor", -1)
	_ev("deal", button)
	_begin_round("bet1")
	return true

## The cold deck: three queens to the plant, a pat flush to the mark, the fourth queen waiting on the bottom.
func _deal_stacked(m: int) -> void:
	var q := 10
	var plant_hand := [card(q, 0), card(q, 1), card(q, 2)]
	var mark_hand := [card(12, 1), card(9, 1), card(7, 1), card(4, 1), card(1, 1)]   # hearts: A J 9 6 3
	var bottom := [card(q, 3)]
	for c in plant_hand + mark_hand + bottom:
		deck.erase(c)
	# two junk cards for the plant to throw away (no pair, no help)
	for c in deck.duplicate():
		if plant_hand.size() >= 5:
			break
		if rank(c) in [0, 5] and suit(c) != 1 and not plant_hand.any(func(x): return rank(x) == rank(c)):
			plant_hand.append(c)
			deck.erase(c)
	# the bottom of the deck (index 0) holds the plant's draw: the queen, then a blank
	var blank: int = deck.pop_back()
	deck.push_front(blank)
	deck.push_front(bottom[0])
	for i in seated():
		if i == plant:
			seats[i].hand = plant_hand
		elif i == m:
			seats[i].hand = mark_hand
		else:
			var h := []
			for _k in 5:
				h.append(deck.pop_back())
			seats[i].hand = h

func _put(i: int, amount: int) -> void:
	var s: Dictionary = seats[i]
	var a := mini(amount, int(s.stack))
	s.stack -= a
	s.bet += a
	s.in_pot += a
	if s.stack <= 0:
		s.all_in = true

func bet_size() -> int:
	return small_bet if phase == "bet1" else big_bet

func _begin_round(p: String) -> void:
	phase = p
	current_bet = 0
	raises = 0
	pending = {}
	for s in seats:
		s.bet = 0
	var able := []
	for i in live():
		if not seats[i].all_in:
			able.append(i)
	if able.size() >= 2:
		for i in able:
			pending[i] = true
	to_act = _next_seat(button, func(i): return pending.has(i))
	if to_act < 0:
		_round_done()

## What the seat to act may do: {fold, check, call: cents, bet: cents, raise: cents (total put in)}.
func legal(i: int) -> Dictionary:
	var s: Dictionary = seats[i]
	var to_call := current_bet - int(s.bet)
	var d := {}
	if to_call > 0:
		d["fold"] = true
		d["call"] = mini(to_call, int(s.stack))
		if raises < cap and int(s.stack) > to_call:
			d["raise"] = mini(to_call + bet_size(), int(s.stack))
	else:
		d["check"] = true
		if int(s.stack) > 0 and raises < cap:
			d["bet"] = mini(bet_size(), int(s.stack))
	return d

func act(i: int, action: String) -> void:
	if phase not in ["bet1", "bet2"] or i != to_act:
		return
	var lg := legal(i)
	if not lg.has(action):
		action = "check" if lg.has("check") else "call"
	var s: Dictionary = seats[i]
	actions_taken += 1
	match action:
		"fold":
			s.folded = true
		"check":
			pass
		"call":
			_put(i, int(lg.call))
		"bet", "raise":
			_put(i, int(lg[action]))
			current_bet = maxi(current_bet, int(s.bet))
			raises += 1
			pending = {}
			for j in live():
				if j != i and not seats[j].all_in:
					pending[j] = true
	s.last = action
	pending.erase(i)
	_ev(action, i, "%d" % int(lg.get(action, 0)))
	if live().size() == 1:
		_finish()
		return
	to_act = _next_seat(i, func(j): return pending.has(j))
	if to_act < 0:
		_round_done()

func _round_done() -> void:
	if live().size() == 1:
		_finish()
	elif phase == "bet1":
		phase = "draw"
		to_act = _next_seat(button, func(j): return not seats[j].out and not seats[j].folded and seats[j].drew < 0)
	elif phase == "bet2":
		_finish()

## The seat to act exchanges the cards at these hand indices (up to three; four when keeping an ace).
func draw(i: int, discard: Array) -> void:
	if phase != "draw" or i != to_act:
		return
	var s: Dictionary = seats[i]
	var idx := []
	for k in discard:
		if int(k) >= 0 and int(k) < 5 and not idx.has(int(k)):
			idx.append(int(k))
	idx.sort()
	var limit := 3
	for k in 5:
		if not idx.has(k) and rank(s.hand[k]) == 12:
			limit = 4
	idx = idx.slice(0, limit)
	var from_bottom := rigged and i == plant
	for k in idx:
		s.hand[k] = deck.pop_front() if from_bottom else deck.pop_back()
	s.drew = idx.size()
	actions_taken += 1
	_ev("draw", i, str(idx.size()))
	if from_bottom and idx.size() > 0:
		_ev("tell_draw", i)
	to_act = _next_seat(i, func(j): return not seats[j].out and not seats[j].folded and seats[j].drew < 0)
	if to_act < 0:
		_begin_round("bet2")

func _finish() -> void:
	var lv := live()
	var scores := {}
	var showdown := lv.size() > 1
	for i in lv:
		scores[i] = best_of(seats[i].hand)
	var won := award(seats, scores, button)
	for i in won.keys():
		seats[i].stack += int(won[i])
	for s in seats:
		s.in_pot = 0
		s.bet = 0
	var winners := []
	for i in won.keys():
		if int(won[i]) > 0:
			winners.append({"seat": i, "amount": int(won[i]), "hand": hand_name(scores[i]) if showdown else ""})
	last_result = {"showdown": showdown, "winners": winners, "scores": scores, "rigged": rigged}
	phase = "done"
	to_act = -1
	_ev("result", winners[0].seat if winners.size() > 0 else -1)

## Split the money everybody put in this hand among the best hands, pot by pot (side pots for anybody all-in).
## Odd cents go to the first winner left of the button. Returns {seat: cents}.
static func award(st: Array, scores: Dictionary, btn: int) -> Dictionary:
	var rem := []
	for s in st:
		rem.append(int(s.in_pot))
	var won := {}
	var n := st.size()
	while true:
		var lvl := 0
		for i in n:
			if scores.has(i) and rem[i] > 0 and (lvl == 0 or rem[i] < lvl):
				lvl = rem[i]
		if lvl == 0:
			break
		var part := 0
		var eligible := []
		for i in n:
			var take := mini(rem[i], lvl)
			part += take
			rem[i] -= take
			if scores.has(i) and take == lvl:
				eligible.append(i)
		_split(part, eligible, scores, btn, n, won)
	# money folded players put in beyond every live hand's stake goes to the best live hand
	var left := 0
	for i in n:
		left += rem[i]
	if left > 0 and not scores.is_empty():
		_split(left, scores.keys(), scores, btn, n, won)
	return won

static func _split(amount: int, eligible: Array, scores: Dictionary, btn: int, n: int, won: Dictionary) -> void:
	var best := -1
	for i in eligible:
		best = maxi(best, int(scores[i]))
	var ws := []
	for k in range(1, n + 1):
		var i := (btn + k) % n
		if eligible.has(i) and int(scores[i]) == best:
			ws.append(i)
	if ws.is_empty():
		return
	var share := amount / ws.size()
	var odd := amount - share * ws.size()
	for w in ws:
		won[w] = int(won.get(w, 0)) + share
	won[ws[0]] += odd

## A void hand (a cheat called and proven): everybody takes back what they put in.
func void_hand() -> void:
	for s in seats:
		s.stack += int(s.in_pot)
		s.in_pot = 0
		s.bet = 0
	last_result = {"showdown": false, "winners": [], "scores": {}, "rigged": rigged, "void": true}
	phase = "done"
	to_act = -1

# ------------------------------------------------------------------ players
## 0..1: how good this hand is right now (before the draw counts what it might become).
func strength(i: int) -> float:
	var h: Array = seats[i].hand
	var sc := eval5(h)
	var cat := category(sc)
	var r := float(_tb(sc, 0)) / 12.0
	if phase == "bet1" or phase == "draw":
		var v: float = [0.05 + r * 0.15, 0.28 + r * 0.27, 0.62 + r * 0.08, 0.78, 0.88, 0.9, 0.95, 0.99, 1.0][cat]
		if cat == 0 and (_flush_draw(h) >= 0 or _straight_draw(h) >= 0):
			v = 0.34
		return v
	return [0.04 + r * 0.14, 0.24 + r * 0.26, 0.56 + r * 0.1, 0.72, 0.82, 0.86, 0.93, 0.98, 1.0][cat]

static func _flush_draw(h: Array) -> int:
	# index of the odd card out when four share a suit, else -1
	for s in 4:
		var n := 0
		var odd := -1
		for k in 5:
			if suit(h[k]) == s:
				n += 1
			else:
				odd = k
		if n == 4:
			return odd
	return -1

static func _straight_draw(h: Array) -> int:
	# index of the card to throw for an open-ended four-straight, else -1
	for k in 5:
		var rs := []
		for j in 5:
			if j != k:
				rs.append(rank(h[j]))
		rs.sort()
		var distinct := true
		for j in 3:
			if rs[j] == rs[j + 1]:
				distinct = false
		if distinct and rs[3] - rs[0] == 3 and rs[3] < 12 and rs[0] > 0:
			return k
	return -1

## What an AI seat does now (a betting action string).
func decide(i: int) -> String:
	var s: Dictionary = seats[i]
	var st: Dictionary = STYLES.get(s.style, STYLES.steady)
	var lg := legal(i)
	var sv := strength(i)
	var roll := rng.randf()
	if rigged and i == plant:
		if lg.has("raise"):
			return "raise"
		if lg.has("bet"):
			return "bet"
		return "call" if lg.has("call") else "check"
	var post := phase == "bet2"
	if lg.has("check"):
		var bet_at: float = (0.70 if post else 0.62) - float(st.aggro) * 0.2
		if lg.has("bet") and (sv > bet_at or roll < float(st.bluff)):
			return "bet"
		return "check"
	var to_call := int(lg.call)
	var price := float(to_call) / float(maxi(pot(), 1))
	if lg.has("raise") and (sv > 0.85 - float(st.aggro) * 0.1 and roll < 0.35 + float(st.aggro) * 0.6):
		return "raise"
	if lg.has("raise") and roll < float(st.bluff) * 0.5 and raises < 2:
		return "raise"
	var need: float
	if post:
		need = 0.62 - float(st.call_down) * 0.38 + price * 0.25
	else:
		need = 0.50 - float(st.loose) * 0.38 + price * 0.2
	if sv >= need or (int(s.in_pot) > int(s.stack) * 2 and sv > need - 0.15):
		return "call"
	return "fold"

## Which cards an AI seat throws away.
func choose_discards(i: int) -> Array:
	var s: Dictionary = seats[i]
	var h: Array = s.hand
	if rigged and i == plant:
		var out := []
		for k in 5:
			if rank(h[k]) != 10:
				out.append(k)
		return out
	var sc := eval5(h)
	var cat := category(sc)
	if cat >= 4 and cat != 7:
		return []
	var keep_ranks := []
	if cat == 7 or cat == 3 or cat == 1 or cat == 2:
		var counts := {}
		for c in h:
			counts[rank(c)] = int(counts.get(rank(c), 0)) + 1
		for r in counts.keys():
			if counts[r] >= 2:
				keep_ranks.append(r)
		var out := []
		for k in 5:
			if not keep_ranks.has(rank(h[k])):
				out.append(k)
		return out
	var fd := _flush_draw(h)
	if fd >= 0:
		return [fd]
	var sd := _straight_draw(h)
	if sd >= 0:
		return [sd]
	if s.style == "bluffer" and rng.randf() < 0.3:
		return []                 # stand pat on nothing: represent a made hand
	# nothing: keep an ace (draw four) or the two highest cards (draw three)
	var order := [0, 1, 2, 3, 4]
	order.sort_custom(func(a, b): return rank(h[a]) > rank(h[b]))
	if rank(h[order[0]]) == 12:
		return order.slice(1)
	return order.slice(2)

func is_player_turn() -> bool:
	return to_act >= 0 and seats[to_act].player

## Let the seat to act play by its style (bots and AI seats).
func auto_step() -> void:
	if to_act < 0:
		return
	if phase == "draw":
		draw(to_act, choose_discards(to_act))
	elif phase in ["bet1", "bet2"]:
		act(to_act, decide(to_act))

## Play one whole hand with every seat on auto (tests and headless bots). Returns false when the table broke up.
func play_auto_hand(max_steps := 400) -> bool:
	if not start_hand():
		return false
	var n := 0
	while phase != "done" and n < max_steps:
		auto_step()
		n += 1
	return phase == "done"

# ------------------------------------------------------------------ self-test (--pokertest)
static func selftest() -> Dictionary:
	var lines: Array = []
	var fails := [0]
	var check := func(ok: bool, what: String) -> void:
		lines.append(("  ok    " if ok else "  FAIL  ") + what)
		if not ok:
			fails[0] += 1
	var E = load("res://src/minigames/poker_engine.gd")
	var cat := func(s: String) -> int: return category(eval5(parse_hand(s)))
	var sc := func(s: String) -> int: return best_of(parse_hand(s))
	# categories
	check.call(cat.call("2s 7h 9d Jc Ks") == 0, "high card")
	check.call(cat.call("Js Jh 9d 4c 2s") == 1, "one pair")
	check.call(cat.call("Ks Kh 5d 5c 2s") == 2, "two pair")
	check.call(cat.call("7s 7h 7d Kc 2s") == 3, "three of a kind")
	check.call(cat.call("5s 6h 7d 8c 9s") == 4, "straight")
	check.call(cat.call("As 2h 3d 4c 5s") == 4, "wheel (ace-low) straight")
	check.call(cat.call("Ts Jh Qd Kc As") == 4, "broadway straight")
	check.call(cat.call("Qs Kh Ad 2c 3s") == 0, "no wrap-around straight")
	check.call(cat.call("2h 7h 9h Jh Kh") == 5, "flush")
	check.call(cat.call("Qs Qh Qd 7c 7s") == 6, "full house")
	check.call(cat.call("9s 9h 9d 9c 2s") == 7, "four of a kind")
	check.call(cat.call("5h 6h 7h 8h 9h") == 8, "straight flush")
	check.call(cat.call("Ah 2h 3h 4h 5h") == 8, "steel wheel")
	# ordering
	check.call(sc.call("2h 7h 9h Jh Kh") > sc.call("Ts Jh Qd Kc As"), "flush beats straight")
	check.call(sc.call("2s 2h 2d 3c 3s") > sc.call("Ah Kh Qh Jh 9h"), "full house beats flush")
	check.call(sc.call("2s 2h 2d 2c 3s") > sc.call("As Ah Ad Kc Ks"), "quads beat a full house")
	check.call(sc.call("2s 3h 4d 5c 6s") > sc.call("As 2h 3d 4c 5s"), "six-high straight beats the wheel")
	check.call(sc.call("Ks Kh 5d 5c Qs") > sc.call("Ks Kd 5s 5h Js"), "two pair kicker decides")
	check.call(sc.call("Ks Kh Qd 5c 4s") > sc.call("Kc Kd Js Th 9s"), "pair kicker decides")
	check.call(sc.call("Qs Qh 4d 4c 2s") > sc.call("Js Jh Td Tc As"), "higher top pair wins two pair")
	check.call(sc.call("As Kh 9d 5c 3s") == sc.call("Ac Kd 9s 5h 3c"), "same ranks, different suits tie")
	check.call(sc.call("Ah Kh 8h 4h 2h") == sc.call("Ac Kc 8c 4c 2c"), "equal flushes tie")
	check.call(sc.call("3s 3h 3d Ac Ks") < sc.call("4s 4h 4d 2c 3c"), "trips by rank, not kickers")
	check.call(category(best_of(parse_hand("2h 5h 9h Jh Kc Kh 3d"))) == 5, "best five of seven finds the flush")
	check.call(category(best_of(parse_hand("9s 9h 9d 4c 4s 4h 2d"))) == 6, "best of seven: two trips make a full house")
	check.call(hand_name(eval5(parse_hand("Js Jh 9d 4c 2s"))) == "a pair of jacks", "names: pair")
	check.call(hand_name(eval5(parse_hand("Qs Qh Qd 7c 7s"))) == "a full house, queens over sevens", "names: full house")
	check.call(hand_name(eval5(parse_hand("As 2h 3d 4c 5s"))) == "a straight to the five", "names: wheel")
	check.call(hand_name(eval5(parse_hand("Ts Js Qs Ks As"))) == "a royal flush", "names: royal flush")
	# side pots: A all-in for 1.00 with the best hand, B and C 3.00 each, B second best
	var st := [{"in_pot": 100}, {"in_pot": 300}, {"in_pot": 300}]
	var won := award(st, {0: 900, 1: 800, 2: 700}, 2)
	check.call(int(won.get(0, 0)) == 300 and int(won.get(1, 0)) == 400 and not won.has(2), "side pot: short stack wins main, next best the side")
	var won2 := award([{"in_pot": 100}, {"in_pot": 100}, {"in_pot": 50}], {0: 500, 1: 500}, 0)
	check.call(int(won2.get(0, 0)) + int(won2.get(1, 0)) == 250 and absi(int(won2[0]) - int(won2[1])) <= 1, "split pot with a folded player's money")
	var won3 := award([{"in_pot": 33}, {"in_pot": 33}, {"in_pot": 33}], {0: 1, 1: 1, 2: 1}, 0)
	check.call(int(won3[1]) == 33 and int(won3[2]) == 33 and int(won3[0]) == 33, "three-way split")
	# whole games: chips are conserved, nobody goes negative, every hand finishes
	var ok_games := true
	var hands := 0
	var showdowns := 0
	var styles_won := {}
	for g in 40:
		var e = E.new()
		e.setup([{"name": "Ruth", "style": "steady", "stack": 1000}, {"name": "Tight", "style": "tight", "stack": 1000},
			{"name": "Loose", "style": "loose", "stack": 1000}, {"name": "Bluffer", "style": "bluffer", "stack": 1000}], 1000 + g)
		var total: int = e.total_chips()
		for k in 30:
			if not e.play_auto_hand():
				break
			hands += 1
			if e.last_result.showdown:
				showdowns += 1
			if e.total_chips() != total:
				ok_games = false
				lines.append("    chips not conserved: game %d hand %d: %d != %d" % [g, k, e.total_chips(), total])
				break
			for s in e.seats:
				if int(s.stack) < 0:
					ok_games = false
		var best := 0
		for i in e.seats.size():
			if e.seats[i].stack > e.seats[best].stack:
				best = i
		styles_won[e.seats[best].style] = int(styles_won.get(e.seats[best].style, 0)) + 1
	check.call(ok_games and hands > 300, "%d auto hands, %d showdowns: chips conserved, no negative stacks" % [hands, showdowns])
	check.call(showdowns > hands / 10 and showdowns < hands, "betting reaches showdowns and folds both happen")
	lines.append("    table leaders by style over 40 games: %s" % str(styles_won))
	# the cold deck: the plant ends with four queens, the mark with a flush, and the plant drew from the bottom
	var r = E.new()
	r.setup([{"name": "Ruth", "style": "steady", "stack": 1000}, {"name": "Del", "style": "bluffer", "stack": 1000},
		{"name": "Hask", "style": "plant", "stack": 1000}, {"name": "Merrow", "style": "tight", "stack": 1000}], 7,
		{"rig_hands": [1], "plant": 2, "mark": 0})
	r.start_hand()
	var told_deal: bool = r.events.any(func(ev): return ev.kind == "tell_deal")
	var n := 0
	while r.phase != "done" and n < 400:
		r.auto_step()
		n += 1
	var told_draw: bool = r.events.any(func(ev): return ev.kind == "tell_draw")
	var plant_quads: bool = category(best_of(r.seats[2].hand)) == 7
	var mark_flush: bool = category(eval5(r.seats[0].hand)) == 5
	check.call(r.rigged and told_deal and told_draw, "rigged hand narrates both tells (deal and bottom draw)")
	check.call(plant_quads and mark_flush, "stacked deck: plant makes four queens, the mark holds a flush")
	var plant_won: bool = r.last_result.winners.size() > 0 and r.last_result.winners[0].seat == 2
	check.call(plant_won, "the cold deck wins the pot")
	# a void hand gives everybody their money back
	var v = E.new()
	v.setup([{"name": "A", "stack": 500}, {"name": "B", "stack": 500}], 3)
	v.start_hand()
	v.auto_step()
	v.void_hand()
	check.call(v.seats[0].stack == 500 and v.seats[1].stack == 500, "void hand returns every stake")
	# draw limits: three cards, four when keeping an ace
	var d = E.new()
	d.setup([{"name": "A", "stack": 500}, {"name": "B", "stack": 500}], 5)
	d.start_hand()
	while d.phase == "bet1":
		d.act(d.to_act, "check" if d.legal(d.to_act).has("check") else "call")
	if d.phase == "draw":
		var who: int = d.to_act
		d.seats[who].hand = parse_hand("As 2h 5d 8c Jh")
		d.draw(who, [1, 2, 3, 4])
		check.call(d.seats[who].drew == 4, "four-card draw allowed when keeping an ace")
		var who2: int = d.to_act
		if who2 >= 0:
			d.seats[who2].hand = parse_hand("Ks 2h 5d 8c Jh")
			d.draw(who2, [1, 2, 3, 4])
			check.call(d.seats[who2].drew == 3, "draw capped at three without an ace")
	return {"ok": fails[0] == 0, "fails": fails[0], "lines": lines}
