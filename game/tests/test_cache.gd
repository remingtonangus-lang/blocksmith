extends RefCounted
## Old cache versions are pruned from user://, current ones kept.

func run(t) -> void:
	var dir := "user://_prune_test"
	DirAccess.make_dir_recursive_absolute(dir + "/audio_v1")
	var cur_world := "world_s1337_v%d.bin" % WorldGen.GEN_VERSION
	var cur_mats := "terrain_mats_v%d_s1337.res" % TerrainMaterials.VERSION
	for n in ["world_s1337_v1.bin", "world_s42_v2.bin", cur_world, "terrain_mats_v1_s1337.res", cur_mats,
			"leaf_atlas_v1.png", "leaf_atlas_v%d.png" % TreeBuilder.VERSION, "settings.cfg", "audio_v1/x.res"]:
		var f := FileAccess.open(dir.path_join(n), FileAccess.WRITE)
		f.store_string("0123456789")
		f.close()
	var freed := G.prune_cache(dir)
	var left := Array(DirAccess.get_files_at(dir)) + Array(DirAccess.get_directories_at(dir))
	left.sort()
	var want := [cur_mats, "leaf_atlas_v%d.png" % TreeBuilder.VERSION, "settings.cfg", cur_world]
	want.sort()
	t.check(left == want, "old cache versions pruned, current kept (left %s)" % str(left))
	t.check(freed == 50, "freed bytes counted (%d)" % freed)
	for n in left:
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)
