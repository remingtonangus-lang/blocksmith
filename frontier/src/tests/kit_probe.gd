extends SceneTree
## Debug helper: build single structures from a settlement plan and print their triangle/box counts.
## godot --headless --path . -s res://src/tests/kit_probe.gd -- --town san_lazaro

func _init() -> void:
	var w := WorldData.new()
	w.load_all()
	var args := OS.get_cmdline_user_args()
	var town := "bitter_spring"
	for i in args.size():
		if args[i] == "--town" and i + 1 < args.size():
			town = args[i + 1]
	var f := w.town(town)
	var is_town := not f.is_empty()
	if f.is_empty():
		f = w.poi(town)
	TownMats.get_all()
	var plan: Dictionary = TownLayout.new().make(w, f, is_town)
	var kit := SettlementKit.new()
	kit.world = w
	for spec in plan.specs:
		var ext := MeshKit.new()
		var inn := MeshKit.new()
		var rec: Dictionary = kit.build(spec, {"ext": ext, "inn": inn, "far": MeshKit.new(), "props": {}, "oprops": {}})
		print("%-32s ext %6d tris  int %6d tris  boxes %4d  spots %3d  doors %2d" % [spec.id, ext.tris, inn.tris, rec.boxes.size(), rec.spots.size(), rec.doors.size()])
	quit()
