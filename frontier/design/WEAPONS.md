# Frontier — firearms art pipeline

Ten original period firearms (`src/combat/weapons.gd`) are generated as detailed, textured, rigged meshes by a
deterministic Blender script, published as `weapons.zip`, and shown in game by `WeaponModel` / `WeaponHolder`.
All makes are fictional: believable 1870s–1890s mechanisms, no real maker's marks, no copied designs or game assets.

| id | type | real-world-correct size | parts |
|---|---|---|---|
| `lockhart_sa` | single-action revolver, solid frame, loading gate, ejector rod | 30 cm | hammer, trigger, cylinder, loading_gate, ejector_rod |
| `sheridan_dao` | double-action top-break, auto-ejector (nickel, hard rubber) | 27 cm | hammer, trigger, barrels > cylinder > ejector |
| `talbot_pocket` | double-action pocket revolver, bird's-head grip, 5 shots | 15 cm | hammer, trigger, cylinder, loading_gate |
| `merriman_lever` | lever repeater, 24" octagon barrel, brass receiver, crescent butt | 108 cm | hammer, trigger, lever, bolt, loading_gate |
| `harlan_carbine` | lever saddle carbine, 20" round barrel, bands, saddle ring | 95 cm | hammer, trigger, lever, bolt, loading_gate |
| `bowden_bolt` | turn-bolt rifle, full stock, handguard, two bands, box magazine | 125 cm | trigger, bolt (lift + draw) |
| `pellman_varmint` | slim .22 bolt rifle, tube magazine | 100 cm | trigger, bolt |
| `vance_rolling` | rolling-block single shot, octagon barrel, tang peep sight | 117 cm | hammer, breech, trigger |
| `calder_double` | side-by-side hammer shotgun, back-action locks, top lever | 113 cm | hammer_r, hammer_l, trigger, trigger_2, top_lever, barrels > extractor |
| `brennan_pump` | exposed-hammer slide-action shotgun | 126 cm | hammer, trigger, pump, bolt |

Finish variants: `lockhart_sa_nickel`, `talbot_pocket_nickel` (nickel + hard rubber), `sheridan_dao_blued`
(blued, case hammer, walnut). `WeaponModel.create(id, finish)` picks `<id>_<finish>.glb`, falling back to `<id>`.

## Pipeline (`tools/weapons/`)
- `gun_gen.py` — entry. `python3 frontier/tools/weapons/gun_gen.py [--only a,b] [--variants] [--out DIR]
  [--tex N] [--preview DIR --views q34,side,detail,front,left --pres 960x540] [--open hammer,lever] [--no-bake]`.
  Default output `frontier/assets/weapons_out/` (gitignored; Godot imports it, `tex/` has a `.gdignore`).
  Needs Python 3.11 + `pip install bpy==5.0.1 numpy scipy pillow`. Deterministic (no RNG without a seed).
  Pistol ≈ 35 s, long gun ≈ 2–5 min on 4 shared cores (Cycles bakes + numpy synthesis).
- `gun_lib.py` — geometry: bevelled side-profile extrusions with filleted corners (`extrude`, `extrude_xz`,
  `extrude_xy`), lofts along the bore with per-station circle/octagon rings that turn back into a visible bore
  (`loft`), swept sections (guards, levers, rings), **pillow** solids for wood (Delaunay-filled outline with a
  rounded-edge thickness profile — stocks, fore-ends, grips), slotted domed screws, booleans (Manifold solver,
  exact fallback), bevel modifiers, smooth shading with sharp edges by angle.
- `gun_rig.py` — `Gun`: semantic material slots mapped per finish (`FINISHES`), static pieces joined into `body`,
  animated parts with pivots (`part(name, pivot, anim, parent)`), markers, texture-region spec (checkering, grooves,
  seam lines, grain axes, handling wear), `scale_all`, grip-origin shift.
- `gun_tex.py` — one UV atlas per weapon (smart project per piece, equal texel density, hidden/tiny pieces shrunk
  with `uvs`, concave pack). Cycles bakes on a joined copy: world position, object normal, UV tangent, material-kind
  id, edge mask (Bevel-node normal vs shading normal) + pointiness, AO (half-res, upsampled). numpy then synthesises:
  blued steel (mottled, plum patina, bright worn edges), case-hardening colours (domain-warped blue/straw/plum/grey),
  nickel (with flaking at wear), brass (tarnish, polished edges), bright steel (machining lines), walnut/oak (rings,
  broad figure, streaked pores), hard rubber, lead, cartridge brass; curvature wear × noise, cavity grime/AO, and a
  tangent-space normal map for checkering (diamond V-grooves with border), knurling, serrations, plate seams, pores.
  Outputs `albedo` (sRGB), `orm` (R AO, G roughness, B metal), `normal` (OpenGL +Y): 1024² pistols, 2048² long guns.
- `models_revolvers.py`, `models_levers.py`, `models_rifles.py`, `models_shotguns.py` — the builders.
- LOD1: all parts merged, decimated to 22 %, 512² textures, node `<id>_lod1`.

## glb convention
- Godot space: barrel along **-Z**, +Y up, +X the gun's right side; metres.
- Root node `<id>` with origin at the **right-hand grip point** (palm centre), identity orientation.
- `body`: all static parts (one mesh). Animated parts are separate nodes whose origin is the pivot; their glTF
  extras (Godot meta `extras`) carry `anim`:
  `{type: "rot", axis: [x,y,z], open: degrees}` · `{type: "slide", axis, open: metres}` ·
  `{type: "bolt", axis (slide), open, rot_axis, rot}`; optional `half` (half-cock degrees), `steps` (cylinder).
  `open` is the fully open/cocked pose from rest. Nested parts follow their parent (top-break cylinder on `barrels`).
- Markers (empties): `muzzle` (-Z = bore direction), `grip_r`, `grip_l` (support hand), `sight_rear`,
  `sight_front`, `holster_attach` (point that sits at the holster/scabbard anchor), `shell_eject` (-Z = eject
  direction).

## Godot API
- `WeaponModel.create(id, finish := "") -> WeaponModel` — loads `res://assets/ext/weapons/<id>.glb` (release) or
  `res://assets/weapons_out/<id>.glb` (local run; un-imported files load through `GLTFDocument` at runtime), else a
  procedural stand-in with the same node/marker names. Methods: `fire_anim()` (trigger, hammer fall, recoil spring,
  then cylinder advance / lever cycle with bolt + hammer / bolt lift-draw-close / pump, timed from `cock_time`,
  case ejection at the right moment), `reload_anim(step)` (0 open, n per round, -1 close: gate + ejector rod +
  cylinder turn, top-break open/eject-all, lever gate push, bolt open/close, break-open with extractor and re-cock,
  rolling-block cock/roll/eject), `cock(ready)`, `pose(dict)`, `pose_open()`, `muzzle_transform()`,
  `grip_transform(name)`, `marker(name)`, `marker_local(name)`, `set_detail(high)` (LOD1 swap); signal
  `ejected(shell, xform)`.
- `WeaponHolder.attach(actor, gun)` (null when headless) — one `WeaponModel` per weapon in `gun.weapons`: sidearm on
  the right hip, long gun slung across the back (or in `saddle` when set), current weapon blended into the hand when
  `gun.drawn` (0.32 s). Hand: a `BoneAttachment3D` on the first bone named `hand.R`, `RightHand`, `hand_r`,
  `mixamorig:RightHand`, ... if the visual has a `Skeleton3D`; else fixed poses for the capsule stand-ins (aimed:
  arm's length at eye height for pistols, shouldered for long guns; drawn but not aimed: low ready). Aims at the
  player's `aim_ray().point` while `intent.aim`, or an NPC's `intent.aim_at`. Watches `gun.fired` (fire_anim +
  smoke) and `gun.reloading` / clip changes (reload steps). `muzzle_transform()`, `has_drawn_model()`.
- `WeaponFX.casing(root, kind, xform, inherit)` (pooled RigidBody brass/hulls that bounce and settle),
  `WeaponFX.smoke(root, pos, dir, amount)` (powder smoke puff).
- Hooks (minimal): `player.gd` / `human.gd` attach a holder after the gun is set up (humans only when they were
  spawned with a weapon) and spawn the muzzle flash at `holder.muzzle_transform()` when a gun is drawn; ballistics
  still use the old body-relative origin.

## Verification
- Blender previews: `gun_gen.py --preview DIR` (Cycles studio: key/fill/rim, gradient world).
- Godot studio: `godot --path frontier res://scenes/weapon_lineup.tscn -- --out /tmp/guns --ids a,b
  --views q34,side,left,detail,open,front,lineup` (src/tests/weapon_lineup.gd).
- In game: `--shot out.png --player --aim [--weapon N] [--fire]` (src/tests/shots.gd) draws and aims.

## Gaps / next
- Hands: no IK yet — the guns hover where the hand would be on the capsule stand-ins; once the character rig
  lands, the holder's bone attach needs a per-rig grip offset and `grip_l` should drive a support-hand IK target.
- VR: `pose()` exposes every part for hand-driven cocking/fanning/loading, but no XR interaction layer uses it yet.
- No individual cartridges travel during reloads (cases eject; new rounds are implied), no carrier/elevator in lever
  guns, no magazine follower; the Brennan bolt and pump move as two parts on one channel.
- Engraving, maker-style roll marks and serials are intentionally absent (no trademarks); wear is uniform per gun
  (could be driven by a `condition` parameter per item instance).
- Holster/scabbard meshes are not part of this pipeline (guns float at the hip/back anchors).
