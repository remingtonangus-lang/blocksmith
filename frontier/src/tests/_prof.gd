extends Node
var last := 0
func _ready():
	process_priority = -1000
func _process(_d):
	var now := Time.get_ticks_usec()
	if last > 0 and now - last > 100000:
		print("SPIKE %.0f ms at frame %d  humans=%d animals=%d" % [(now-last)/1000.0, Engine.get_process_frames(), get_tree().get_nodes_in_group("humans").size(), get_tree().get_nodes_in_group("animals").size()])
	last = now
