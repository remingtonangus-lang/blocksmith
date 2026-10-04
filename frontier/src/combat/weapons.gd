class_name Weapons
extends RefCounted
## Period firearms of the Sable River country (original makes and names). Numbers are tuned for readable,
## lethal gunfights: a revolver drops a man in 2-3 body hits or 1 head hit; rifles reach and punch harder;
## shotguns devastate up close and fall off fast.
## Fields: kind (pistol/rifle/shotgun), slot (sidearm/longarm), damage (per projectile), pellets, range (m, full
## damage), falloff (m, zero damage), rpm (max cyclic rate), action (single/double/lever/pump/bolt/break),
## cock_time (s between shots when manually cycling), capacity, reload_each (s per round) or reload_all,
## spread (deg, hip), aim_spread (deg, aimed), recoil (camera kick deg), velocity (m/s), ammo, sound.

const DEFS := {
	"lockhart_sa": {"name": "Lockhart .44 Single Action", "kind": "pistol", "slot": "sidearm", "damage": 38.0,
		"pellets": 1, "range": 30.0, "falloff": 90.0, "action": "single", "cock_time": 0.42, "capacity": 6,
		"reload_each": 0.55, "spread": 2.2, "aim_spread": 0.45, "recoil": 4.5, "velocity": 290.0,
		"ammo": "revolver", "sound": "revolver_heavy", "price": 45},
	"sheridan_dao": {"name": "Sheridan Double Action", "kind": "pistol", "slot": "sidearm", "damage": 30.0,
		"pellets": 1, "range": 25.0, "falloff": 75.0, "action": "double", "cock_time": 0.28, "capacity": 6,
		"reload_each": 0.5, "spread": 2.8, "aim_spread": 0.6, "recoil": 3.6, "velocity": 260.0,
		"ammo": "revolver", "sound": "revolver_light", "price": 60},
	"merriman_lever": {"name": "Merriman Repeater", "kind": "rifle", "slot": "longarm", "damage": 46.0,
		"pellets": 1, "range": 70.0, "falloff": 220.0, "action": "lever", "cock_time": 0.62, "capacity": 13,
		"reload_each": 0.6, "spread": 3.0, "aim_spread": 0.25, "recoil": 5.5, "velocity": 400.0,
		"ammo": "repeater", "sound": "rifle_lever", "price": 90},
	"harlan_carbine": {"name": "Harlan Saddle Carbine", "kind": "rifle", "slot": "longarm", "damage": 40.0,
		"pellets": 1, "range": 55.0, "falloff": 170.0, "action": "lever", "cock_time": 0.5, "capacity": 10,
		"reload_each": 0.55, "spread": 2.6, "aim_spread": 0.3, "recoil": 4.8, "velocity": 380.0,
		"ammo": "repeater", "sound": "rifle_lever", "price": 75},
	"bowden_bolt": {"name": "Bowden Bolt Rifle", "kind": "rifle", "slot": "longarm", "damage": 85.0,
		"pellets": 1, "range": 160.0, "falloff": 450.0, "action": "bolt", "cock_time": 1.15, "capacity": 5,
		"reload_each": 0.7, "spread": 4.0, "aim_spread": 0.1, "recoil": 9.0, "velocity": 700.0,
		"ammo": "rifle", "sound": "rifle_bolt", "price": 150},
	"calder_double": {"name": "Calder Double-Barrel", "kind": "shotgun", "slot": "longarm", "damage": 13.0,
		"pellets": 9, "range": 10.0, "falloff": 38.0, "action": "break", "cock_time": 0.32, "capacity": 2,
		"reload_all": 1.9, "spread": 5.0, "aim_spread": 3.6, "recoil": 11.0, "velocity": 330.0,
		"ammo": "shotgun", "sound": "shotgun", "price": 70},
	"brennan_pump": {"name": "Brennan Slide-Action", "kind": "shotgun", "slot": "longarm", "damage": 11.0,
		"pellets": 9, "range": 9.0, "falloff": 34.0, "action": "pump", "cock_time": 0.75, "capacity": 5,
		"reload_each": 0.62, "spread": 5.5, "aim_spread": 4.0, "recoil": 9.5, "velocity": 320.0,
		"ammo": "shotgun", "sound": "shotgun", "price": 110},
	"pellman_varmint": {"name": "Pellman .22 Varmint", "kind": "rifle", "slot": "longarm", "damage": 16.0,
		"pellets": 1, "range": 45.0, "falloff": 120.0, "action": "bolt", "cock_time": 0.7, "capacity": 7,
		"reload_each": 0.5, "spread": 2.5, "aim_spread": 0.3, "recoil": 1.5, "velocity": 370.0,
		"ammo": "varmint", "sound": "rifle_small", "price": 40},
	"talbot_pocket": {"name": "Talbot Pocket Pistol", "kind": "pistol", "slot": "sidearm", "damage": 22.0,
		"pellets": 1, "range": 12.0, "falloff": 40.0, "action": "double", "cock_time": 0.3, "capacity": 5,
		"reload_each": 0.5, "spread": 3.5, "aim_spread": 1.0, "recoil": 2.5, "velocity": 230.0,
		"ammo": "revolver", "sound": "revolver_light", "price": 30},
	"vance_rolling": {"name": "Vance Rolling Block", "kind": "rifle", "slot": "longarm", "damage": 95.0,
		"pellets": 1, "range": 180.0, "falloff": 500.0, "action": "single", "cock_time": 1.6, "capacity": 1,
		"reload_each": 1.2, "spread": 4.5, "aim_spread": 0.08, "recoil": 11.0, "velocity": 520.0,
		"ammo": "rifle", "sound": "rifle_heavy", "price": 120},
}

## Damage multipliers per hit zone (bone groups decide the zone).
const ZONES := {"head": 3.2, "neck": 2.2, "chest": 1.25, "belly": 1.0, "arm": 0.55, "leg": 0.6}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["lockhart_sa"])

## Damage at distance d (linear falloff between range and falloff distance).
static func damage_at(def: Dictionary, d: float) -> float:
	var f := 1.0
	if d > def.range:
		f = clampf(1.0 - (d - def.range) / maxf(def.falloff - def.range, 1.0), 0.15, 1.0)
	return def.damage * f
