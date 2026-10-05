extends Node3D
## Minimal stand-in actor for render tests (combat_fx): what WeaponHolder reads from a Human/player.
var visual: Node3D
var intent := {"aim_at": null}
var alive := true
var facing := 0.0
