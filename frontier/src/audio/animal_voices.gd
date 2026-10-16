class_name AnimalVoices
extends RefCounted
## Animal voices for gameplay events (alarm, attack, flush, calls at their hours) through Game.audio.play, at the
## animal's position. Prefers the CI's Commons CC0/PD recordings (rec_*) over the synthesised fallbacks
## (tools/audio/sfx_creatures.py). Counts plays per id for the audio oracle (`--bot birds`, `--bot hunt`).

const REC := {"wolf_howl": "rec_wolf_howl", "elk_bugle": "rec_elk_bugle", "turkey_gobble": "rec_turkey_gobble",
	"bird_caw": "rec_crow_caw", "bird_hawk": "rec_hawk_scream", "deer_snort": "rec_deer_snort", "bear_huff": "rec_bear_huff",
	"coyote_yip": "rec_coyote", "coyote_chorus": "rec_coyote", "horse_whinny_synth": "rec_horse_whinny",
	"horse_snort": "rec_horse_snort"}

static var plays := {}               # id asked for -> count (whether or not the audio build has it)

static func pick(id: String) -> String:
	var a = Game.get("audio")
	if a == null:
		return id
	var r: String = REC.get(id, "")
	if r != "" and a.has_sound(r):
		return r
	return id

static func play(id: String, pos: Vector3, opts: Dictionary = {}) -> void:
	plays[id] = int(plays.get(id, 0)) + 1
	var a = Game.get("audio")
	if a == null or not a.get("ok"):
		return
	var sid := pick(id)
	if a.has_sound(sid):
		a.play(sid, pos, opts)
