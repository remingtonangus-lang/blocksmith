extends RefCounted
## Look curve: deadzone, monotonic response, acceleration only at the edge, sun path sanity.


func run(t) -> void:
	var c: Node = load("res://scripts/core/controls.gd").new()
	t.check(c.shape_look(Vector2(0.05, 0.0), 0.016, false) == Vector2.ZERO, "inside the centre deadzone = no look")
	var prev := 0.0
	var mono := true
	for i in range(12, 101):
		var v: Vector2 = c.shape_look(Vector2(i / 100.0, 0.0), 0.016, false)
		if v.x < prev - 1e-6:
			mono = false
		prev = v.x
	t.check(mono, "look response is monotonic")
	var slow: Vector2 = c.shape_look(Vector2(1.0, 0.0), 0.016, false)
	for i in 60:
		c.shape_look(Vector2(1.0, 0.0), 0.016, false)
	var fast: Vector2 = c.shape_look(Vector2(1.0, 0.0), 0.016, false)
	t.check(fast.x > slow.x * 1.1, "acceleration ramps up at full deflection")
	c._accel_t = 0.0
	var zoom: Vector2 = c.shape_look(Vector2(0.5, 0.0), 0.016, true)
	c._accel_t = 0.0
	var nz: Vector2 = c.shape_look(Vector2(0.5, 0.0), 0.016, false)
	t.check(zoom.x < nz.x, "zoomed look is slower")
	c.free()
	var noon := SkySystem.sun_vector(12.0)
	var night := SkySystem.sun_vector(0.0)
	var morning := SkySystem.sun_vector(7.0)
	t.check(noon.y > 0.7, "sun high at noon (%.2f)" % noon.y)
	t.check(night.y < -0.3, "sun below the horizon at midnight")
	t.check(morning.x > 0.3, "sun in the east in the morning")
	t.check(noon.z > 0.0, "noon sun in the south (+z)")
