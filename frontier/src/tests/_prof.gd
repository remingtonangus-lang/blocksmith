extends Node
var last := 0
func _ready():
	process_priority = -1000
var _mem_t := 0.0
func _process(_d):
	_mem_t += _d
	if _mem_t > 10.0:
		_mem_t = 0.0
		print("MEM static %.0f MB  objects %d  nodes %d  resources %d  tex %.0f MB  buf %.0f MB  video %.0f MB" % [
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	var now := Time.get_ticks_usec()
	if last > 0 and now - last > 100000:
		var parts := []
		for k in Game.prof_acc.keys():
			parts.append("%s=%.0f" % [k, Game.prof_acc[k] / 1000.0])
		print("SPIKE %.0f ms at frame %d  humans=%d animals=%d  %s" % [(now-last)/1000.0, Engine.get_process_frames(), get_tree().get_nodes_in_group("humans").size(), get_tree().get_nodes_in_group("animals").size(), " ".join(parts)])
	Game.prof_acc.clear()
	last = now
