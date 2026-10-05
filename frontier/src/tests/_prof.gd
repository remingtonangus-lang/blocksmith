extends Node
var last := 0
func _ready():
	process_priority = -1000
func _process(_d):
	var now := Time.get_ticks_usec()
	if last > 0 and now - last > 100000:
		var parts := []
		for k in Game.prof_acc.keys():
			parts.append("%s=%.0f" % [k, Game.prof_acc[k] / 1000.0])
		print("SPIKE %.0f ms at frame %d  humans=%d animals=%d  %s" % [(now-last)/1000.0, Engine.get_process_frames(), get_tree().get_nodes_in_group("humans").size(), get_tree().get_nodes_in_group("animals").size(), " ".join(parts)])
	Game.prof_acc.clear()
	last = now
