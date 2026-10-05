class_name LocoAccents
extends RefCounted
## Locomotion accents on top of the blend-space gait (mocap one-shots on the full-body action layer): turning on the
## spot steps through turn_in_place_L/R instead of spinning, a hard stop from a run plays run_stop and one from a brisk
## walk plays walk_stop. Root motion stays extracted, so the procedural facing still drives the body's rotation.

var _prev_yaw := 0.0
var _prev_speed := 0.0
var _cool := 0.0
var _peak := 0.0                 # recent top speed (decays): stops are judged against it, not the last frame
var _started := false
var played := {}

func tick(visual: Node, facing: float, speed: float, dt: float, busy := false) -> void:
	if visual == null or not visual.has_method("play_action") or dt <= 0.0:
		return
	if not _started:
		_prev_yaw = facing
		_prev_speed = speed
		_started = true
		return
	_cool -= dt
	_peak = maxf(speed, _peak - dt * 1.5)
	var yaw_rate := angle_difference(_prev_yaw, facing) / dt
	var clip := ""
	if not busy and _cool <= 0.0:
		if speed < 0.35 and absf(yaw_rate) > 1.2:
			clip = "turn_in_place_L" if yaw_rate > 0.0 else "turn_in_place_R"
		elif _peak > 4.2 and speed < 1.4 and speed < _prev_speed:
			clip = "run_stop"
		elif _peak > 1.9 and _peak <= 4.2 and speed < 0.5 and speed < _prev_speed:
			clip = "walk_stop"
	if clip != "":
		var length: float = visual.play_action(clip)
		if clip.ends_with("_stop"):
			_peak = 0.0
		if length > 0.0:
			_cool = minf(length * 0.8, 1.2)
			played[clip] = int(played.get(clip, 0)) + 1
	_prev_yaw = facing
	_prev_speed = speed
