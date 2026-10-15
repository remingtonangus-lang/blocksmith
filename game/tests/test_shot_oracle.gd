extends RefCounted
## The shot image oracles flag black, blown-out, magenta (missing texture) and flat frames, and pass a real-looking one.

const Shots := preload("res://scripts/core/shots.gd")


func run(t) -> void:
	var w := 320
	var h := 180
	var black := Image.create(w, h, false, Image.FORMAT_RGB8)
	black.fill(Color(0.0, 0.0, 0.0))
	t.check(Shots._image_oracle(black).begins_with("FAIL black frame"), "black frame flagged")
	var white := Image.create(w, h, false, Image.FORMAT_RGB8)
	white.fill(Color(1, 1, 1))
	t.check(Shots._image_oracle(white).contains("blown out"), "blown-out frame flagged")
	var ok := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			ok.set_pixel(x, y, Color(0.2 + 0.6 * float(y) / h, 0.3 + 0.4 * float(x) / w, 0.5))
	t.check(Shots._image_oracle(ok).begins_with("ok"), "a graded frame passes (%s)" % Shots._image_oracle(ok))
	var mag := ok.duplicate() as Image
	mag.fill_rect(Rect2i(0, 0, 40, 40), Color(1, 0, 1))
	t.check(Shots._image_oracle(mag).contains("missing textures"), "magenta patch flagged")
	var flat := Image.create(w, h, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.5, 0.5, 0.5))
	t.check(Shots._image_oracle(flat).contains("flat frame"), "flat frame flagged")
