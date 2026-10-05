# Settlements — architecture, API, status

Every town and point of interest in `world.features` is planned at boot and built in full detail by a procedural
1899 building kit when the camera comes near. Entry point: `src/world/settlements.gd` (`setup(world)` from main.gd,
unchanged API).

## Files

| File | Role |
|---|---|
| `src/world/settlements.gd` | Orchestrator: plans all settlements, paints streets/yards into the terrain control map, far shells, streaming detail builds (worker thread → main-thread attach), doors, lights, probes, navmesh baking, the AI API |
| `src/world/town_layout.gd` | Planner: town frame on the feature's `angle`, main street, side streets, lots both sides with alleys, programs per town/POI, road connectors, river bridge, depot + track + water tower by the rail, street furniture, footprint checks (river, lake, rail, slope, overlaps) |
| `src/world/building_gen.gd` | Kit core: frames/walls with real openings, windows (casing, sash, muntins, glass, shutters), doors, floors, gable/shed/flat roofs, chimneys, boardwalks + steps + railings, hitching rails, troughs, lamp posts, signs, far-LOD helpers, collision boxes, spots, rooms, lights |
| `src/world/building_styles.gd` | Exterior styles: `false_front`, `two_storey` (saloon/hotel with balcony), `brick` (2–3 storeys, bank), `house`, `cabin` (log), `church` (steeple + belfry), `school`, `barn` (livery), `smithy`, `depot` (+ platform), `adobe` (vigas, portal), `tent`, `outhouse`, `shed` |
| `src/world/interiors.gd` | Furnishing per type: saloon (bar, back bar, mirror, bottles, tables, piano, upstairs rooms), hotel (desk, key board, lobby, rooms), store (shelves of goods, counter, display case, stove), gunsmith, sheriff (desk, gun rack, posters, cells), bank (teller grilles, vault), doctor, barber (chairs, bath), undertaker (coffins), post/telegraph/newspaper/land office, restaurant, butcher, church (pews, chancel), school (desks, blackboard), livery (stalls, hay), smithy (forge, anvil), depot (benches, ticket office, freight), house, cabin, tent, cantina, boarding house, warehouse, assay office |
| `src/world/structures.gd` | `SettlementKit` (final class): water tower, windmill (spinning wheel) + tank, mining head-frame + ore bin + tailings, bridge, pier, Port Linden bluff stair, wagons, corrals, campfire, well, woodpile, log piles, sawmill, mission ruin, station track, street kit (lamps, troughs, hitching rails, barrels, crates, benches, sign posts, pumps, telegraph poles with wires) |
| `src/world/mesh_kit.gd` | Packed-array geometry builder (per-material buckets, metre UVs, tint/weathering/dirt attributes), commit + position-only shadow proxy |
| `src/world/town_mats.gd` | Shared materials: one `building.gdshader` material per packed CC0 set, glass, sign paint, iron, brass, lamp glow, fire, water, bottle, cloth, mirror, far |
| `src/world/props.gd` | Poly Haven CC0 props (glTF) loaded once (threaded preload), flattened to one mesh, colour variants (`name@stain`) |
| `src/world/sign_text.gd` | MSDF sign lettering from OFL fonts (atlases cached in `user://sign_atlas/`) |
| `src/world/door.gd` | `TownDoor`: hinged/batwing door leaf (MultiMesh instance + AnimatableBody3D) with `interact()` |
| `shaders/building.gdshader` | Walls/roofs/floors: packed albedo+height / normal+roughness+AO, paint tint (sRGB), weathering, board tone variation, ground splash dirt, rain |
| `shaders/window.gdshader` | Wavy period glass, grime, lit windows at night |
| `shaders/sign_text.gdshader` | MSDF letters with chipped paint |
| `src/tests/kit_probe.gd` | Per-structure triangle/collision/spot counts |

## Conventions
- Building local frame: x across the frontage, z from the front wall (0) to the back (d), y from the ground floor;
  the front faces −z (the street). Porches/boardwalks at z < 0, boardwalk floor ≈ 0.45 m above the street with
  steps (and ramp collision) at doors and at the ends of each boardwalk run; touching boardwalks share one level.
- Proportions: doors 2.1–2.3 m (shop doors with transoms), storeys 3.3–3.6 m (ground floor of stores 3.6–4.0 m),
  windows sill 0.85 m, display windows 0.6–2.7 m, wall 0.15 m frame / 0.3 m brick / 0.5 m adobe.
- UVs are metres (texture scale per material: ~0.18 m siding boards, 0.075 m brick courses); vertical members get
  vertical grain automatically.

## Rendering and performance
- Boot: plans + far shells for all 12 settlements (~1–3 s on the cloud CPU), the spawn town built synchronously.
- Streaming: a settlement's detail is built on a `WorkerThreadPool` task when the camera is within 750 m of its
  edge; nodes, collision, doors and lights are created on the main thread (~15–40 ms per town).
- Per 128 m cell: one exterior mesh (one surface per material, to 520 m, no shadow casting) + one position-only
  shadow proxy (SHADOWS_ONLY), one interior mesh (to 140 m, no shadows), prop MultiMeshes (interior 140 m, street
  200 m), door MultiMeshes (300 m). Far shell per settlement from 480 m (one surface).
- Lights: OmniLights per lamp/porch/room/fire, culled beyond 140 m, distance-faded at 45–80 m, at most two shadowed
  lights per town; lit windows and lamp glass are emissive materials driven by the night factor.
- Interior ReflectionProbes (one per furnished building, update once, interior ambient colour).
- Numbers (cloud software renderer, 960×540; whole frame incl. terrain/vegetation): see the status note.

## API for town life / AI (`Game.main.settlements`)
```
get_town(id) -> {id, name, kind, center, frame, radius, state, buildings: [ids], doors: [ids], spots: [...],
                 streets: [{a, b, w}] (town space), nav_regions, node}
get_building(id) -> {id, town, type, name, role, hours [open, close], transform, size, floor_y, storeys,
                     enterable, doors: [ids], door_specs, spots, rooms [{name, rect (local x/z), y, floor_y}],
                     lights, body, probe}
spots(town_id, type := "") -> [{type, transform, building, town, ...}]
nearest_spot(pos, type, max_dist := 60) -> Dictionary
door(id) -> TownDoor; nearest_door(pos, max_dist := 2.5); interact_nearest(pos, max_dist := 2.5) -> bool
town_at(pos, margin := 30) -> id; building_at(pos) -> id (inside an enterable footprint)
ensure_built(id) (blocking); signal town_built(id)
bake_navigation(id) (64 m chunks, async; automatic when the player is within 350 m); navigation_ready(id)
night_factor() -> 0..1
```
Spot transforms: the actor stands at `origin` and faces −Z of the basis (Godot forward). Extras: `sit_height`
(chairs 0.46, benches/porches 0.45, barber chair 0.6), `lie_height` + `head` (beds, cots, exam table), `work`
(bar, counter, desk, forge, anvil, telegraph, tickets, freight, cook, teach, preach, mine, saw, chop, water…),
`door` (door id for door_in/door_out), `table`, `cell`, `animal` (stall/corral), `lean` (bar patrons).

Spot types: door_out, door_in, bartender, bar_patron, chair, piano, stand, balcony, balcony_door, bed, clerk,
desk_customer, shopkeeper, shop_counter, work, teller, bank_customer, banker_desk, doctor_desk, patient,
barber, barber_chair, bath, sheriff_desk, cell_bunk, telegrapher, cook, preacher, teacher, ticket_agent,
ticket_customer, platform, stall, corral, trough, hitch, porch_sit, outhouse, bench, campfire, campfire_seat,
wagon_seat, well, pump, water_tower, pier_end, fishing.

Doors: `TownDoor.interact(by)` toggles (opens away from `by`), `open_from(pos, hold)` for NPCs walking through
(auto-closes), `push(from)` for saloon batwings (spring back), `is_open()`, signals `opened`/`closed`.

Navigation: NavigationMesh cell 0.25 m, agent radius 0.25, height 1.75, climb 0.25 (boardwalks need the steps),
slope 38°; built from the settlement colliders + the terrain inside the town disc (water excluded), 64 m chunks
baked three at a time. Every doorway also gets a two-way `NavigationLink3D` (0.9 m outside -> 0.9 m inside):
narrow, oblique door openings don't survive voxelisation at radius 0.25 reliably, the links make every room
reachable. `--settlements_test --build <town> --nav <town> --navcheck` paths from the main street to every
ground-floor standing spot and lists the ones it can't reach (Bitter Spring: 31 of 485, all seats within 0.8 m
of the navmesh, outhouses, cells, the livery aisle and depot freight room).

## Town life (src/ai/population.gd, schedule.gd, routine.gd)
- **Cast** (`TownSchedule.cast`): stable per town (seeded by town id): one worker per job building (role ->
  job: bartender, storekeeper, gunsmith, butcher, banker + teller, sheriff + night deputy, barber, doctor,
  undertaker, postmaster, clerk, editor, blacksmith, stablehand, preacher, teacher, station agent, hotelier,
  cook), residents (townsmen, women, ladies, elders, matrons, drinkers, ranch hands in town, a gambler, two
  drunks) and children where there is a school. Homes are the houses/cabins (several per house), else the hotel.
  Looks are assigned per town without repeats while the catalogue lasts (36 adult looks).
- **Schedule** (`TownSchedule.block(resident, hour, weekday, index)`): work during the building's `hours`
  (opening a little early or late per person, Sunday closed for shops, saloon from noon on Sunday), noon at the
  cafe, errands as a customer at open shops (counter, bank window, ticket window, barber chair, doctor's bench),
  loitering (wall leans beside shop doors, porch seats, hitch rails, troughs, depot benches), evening at the saloon
  (bar rail, tables, the card table) or the porch, Sunday service, school 8–14:30 then play in the yard, the
  sheriff's desk with a patrol along the main street every third hour, the deputy on nights, drunks staggering
  outside the saloon 21:30–2, everybody else home (indoors = despawned) by 23.
- **Routine** (`TownRoutine`): claim a spot (population keeps claims; upstairs spots skipped), walk the navmesh
  (own path follower on the town map; doors opened ahead via `TownDoor.open_from` and held with `keep_open`),
  arrive and anchor on the spot (`Human.anchor_to`: kinematic, no collision move) with an activity loop chosen
  per spot type (`sit_idle`, `drink`, `drink_smoke`, `lean_wall`, `talk_1/2`, `idle_wait`...) and `sit_down` /
  `stand_up` gestures, dwell with gestures (`pick_up`, `shrug`, `talk_directions`, `drink`) and neighbour looks,
  strollers who meet stop to chat. Unreachable spots are marked and skipped; a snagged walker glides along its
  path for a moment. Far from Ruth and out of view, trips are skipped (teleport) to keep distant towns cheap.
- **Reactions** (brain.gd): look at Ruth within 7 m, greet (time-of-day lines per voice type, wave; wary or rude
  after she threatened them or with low Standing; remembered per resident), run inside the nearest doorway from
  gunfire (alarm bark) and cower, witnesses run to the nearest lawman or the sheriff's door (`on_witness` ->
  `on_report`), lawmen answer brandishing with "keep that iron holstered" and cover her, serious crimes with
  arrest/combat; a levelled gun close by makes civilians cower or flee ("Don't shoot!"); bumped residents step
  aside; after shooting stops people gather round bodies in the street (`population.spectacle`). Everything
  calms back into the routine after 20–40 s.
- **Story scenes**: a resident on a spot that a mission actor (src/missions/places.gd) stands on moves on and
  leaves the spot to the story.
- **Metrics** (town bot): `town metric: N residents of a C cast | on schedule % | spots reached a of w walks |
  skipped unseen | went home | doors used | stuck (per NPC-minute) | chats, greetings, nudges | draw calls`.

## Unloading and the rail line
- Settlements whose edge is more than 1.3 km from the camera drop their detail (meshes, colliders, doors, lights,
  navmesh, spot records; residents despawn); plan, far shell and ground paint stay and the town is rebuilt on
  return (`settlements.unload(id)`).
- `src/world/rail_line.gd`: the main line between towns from `features.rail` (towns build their own station track
  within radius + 60 m): ballast, ties every 0.6 m, rails, timber trestle bents where the grade is >1.2 m above
  ground or over water; ~200 m detail chunks built on a worker thread within 520 m (visible to 480 m), one
  vertex-coloured far strip per ~1.6 km (always on, just under the detail ballast).

## Town characters
- **Bitter Spring** (rail town): 20 m main street on 18°, two side streets, false fronts + two-storey hotel and
  saloon with balconies, brick bank and land office, sheriff with cells, livery + corral, smithy, church closing
  the west end, school, depot + platform + track + water tower + stock pen, windmill, houses, bridge over the Sable.
- **Coldwater** (mining camp): narrow muddy street, raw-plank false fronts, tent store, assay office, boarding
  house, tents and cabins on the slopes, head-frame + hoist house + ore bin + tailings.
- **Mesquite Wells** (desert stop): adobe and plaster buildings with portals and vigas around a plaza with a well,
  cantina, chapel, stage station, depot + water tower (water stop), windmill, corrals.
- **Port Linden** (port town): 2–3 storey brick blocks with cast-iron fronts and corbelled cornices, hotel, bank,
  newspaper, railroad office, chandlery, warehouse, church, school, many houses, depot, bluff stair to the pier.
- POIs: outfit camp (tents, covered and chuck wagons, campfire with seats, picket line), Halvorsen Ranch (ranch
  house, barn, corral, bunkhouse, windmill), homesteads, logging camp (bunkhouse, cookhouse, sawmill, log decks),
  San Lazaro mission ruin, Greer's trading post, trapper's cabin.

## Worldgen changes made for settlements (tools/worldgen.py)
Towns are flattened before the rivers are carved (the Sable no longer floats over Bitter Spring); settlement cores
keep their flat ground (no floodplain lowering, no fine rock noise); the railroad is pinned to town level through
towns (no 6 m embankment through main street; approaches become cuttings/fills).

## Known gaps / next
- Interiors are furnished for every enterable building, but upper floors of brick blocks are empty rooms; no
  kitchens/back rooms beyond store back rooms; no rugs/curtains variety; props are the Poly Haven set only (no
  pianos, billiard tables, stoves, bathtubs as models — procedural stand-ins).
- Doors: no locking/ownership; batwing doors have no collision (they swing when pushed via `push()`).
- Lighting: interior look depends on the renderer preset (SSIL/SDFGI on High help a lot); ReflectionProbes need a
  frame or two after attach; window light shafts are not modelled.
- Navigation: chunked bake per town on demand; no off-mesh links for ladders; furniture is carved from the navmesh
  only where it has collision boxes (tables, counters, beds, stoves), not small props.
- Mission ruin, logging camp and trapper's cabin are simpler than the towns.
- Railroad: no switches, sidings, bridges with girders or trains yet.
- Town life: no child character models (children are the youngest adult looks scaled to 0.74 — reads as
  teenagers at best); no hands-up / cowering clip (crouch idle stands in); no melee, so "crowding round a fight"
  hooks onto bodies after a gunfight and the `spectacle(pos)` API; bar patrons have no glass prop in hand; ambient
  NPC-to-NPC dialogue is animation only (the voice set has no NPC-to-NPC lines); beds are not used (home =
  indoors/despawned).
