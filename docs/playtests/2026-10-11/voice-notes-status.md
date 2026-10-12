# Oct 11 playtest notes: status per backlog item (Lane A thread)

Each P item from docs/roadmap/backlog.md, what was found, what changed and the check that holds it. Checks named
`P..` run in `questcheck --p11-only` (Linux host) and the Mac `--questbugs` (Sources/PlaytestOct11Tests.swift)
unless another suite is named.

| Item | Status | What changed | Check |
|---|---|---|---|
| P1 ice in water | fixed | water faces against ice are culled | P1 ice in water |
| P2 stacked sugar cane | fixed | seamless cane texture and stacked cross quads | texture repack |
| P3 driprock upside down | fixed | floor driprock points up, hanging points down | P3 driprock |
| P4 trees through the ground | fixed | dark-cave fog ends inside the far ring | P4 cave sight |
| P5 dropped stacks | fixed | piles of 1-5 copies by stack size | P5 dropped stacks |
| P6 sign text | fixed | each line scaled to fit its board | P6 sign text |
| P7 iron ore | fixed | higher-contrast iron ore texture | texture repack |
| P8 distant volcano | fixed | far-view haze fades the cone into the loaded terrain instead of a hollow shell | render `_volcanoP8.png` at his 08:47 view |
| P9 inventory hold | fixed | Y opens the inventory faster | QuestSim |
| P10 crafting tiles | fixed | 15 tiles of 33 px, controller-sized | P10 crafting tiles |
| P11 height on HUD | fixed | Y shown with X and Z | P11 coordinates |
| P12/P38 hunger | fixed | drain from sprinting, fighting and jumping; walking costs none | P12 hunger |
| P13/P16 VR melee | fixed | contact from any direction (uppercut, low chop), 0.16 s rehit, damage scales with swing speed, red slash mark | QuestSim swingPath |
| P14 footsteps / unknown sound | fixed (sound inferred) | dry steps crisper (less low thud, more grit, shorter ring); the cave sting's low drone removed (the 09:17 sound is inferred to be it) | P14 footsteps |
| P15 22 fps at high render distance | fixed | the render-distance governor acts on a severe overrun even while chunks load | rdgovernor trace 5 |
| P17 held sword | fixed | held items are one extruded mesh with texel walls | QuestSim P17 |
| P18 lava at a border | fixed (part 1) | fluid against air across a chunk border starts flowing when the chunks meet | P18 lava at a chunk border |
| P18 water falling one block | open (T5) | the waterstep scene now flows; renders match the reference, no defect pinned; needs a headset look | `--scene waterstep` |
| P19 deep dark copy | fixed | murk depths, the Buried Citadel and the stalker summons removed; remaining close copies listed in docs/status/ip-content-audit-oct11.md (G20) | P19 no murk depths |
| P20 through a wall | fixed | unstuck tries the nearest free spot before popping up | P20 unstuck |
| P21 unclear objects | part | border posts carry signs at both ends; the 13:03 "eye" needs the voice shot (Mac worker, device checklist) | countries P21 border post |
| P22 coral | fixed | reefs are domed coral heads of one species each, caps, branching fingers, fans round the rim, seagrass lanes | view render at his 12:53 spot |
| P23 cleared bases | fixed | a citadel whose garrison is dead is cleared for good: no patrols of fresh troops, lifetime cap of two dropships, no Kestrel, no rebuild crew | basetest cleared |
| P24 things to steal | fixed | every shop keeps a filled till chest behind its counter (houses already had chests) | towns P24 |
| P25 auto-placing | fixed | holding use repeats only the item the press began with; a menu ends the hold | P25 held use |
| P26 horses | fixed (animation to the Mac worker) | taming bar with "Bucking: sit still" / "Pat it now"; bonding levels need 200/600/1400 xp (pats 2, brush 10, treats 2, riding 1 per 40 m); pace 8-17 m/s by breed; hold B whistles the horse to 4.5 blocks, a spare horse stops 3.5 away; a downed horse dies to the next melee hit | horse tests, P26 horses |
| P27 monsters in daylight | fixed | at full daylight, out of sight and under open sky, hostile mobs (not sun-burners, not in rain) fade out over about 8 s | P27 day clears |
| P28 craft counts | fixed | each recipe tile shows how many you can make; the detail panel says "You can make N" | P28 craft tiles |
| P29 prices | part | map $1.50, raw titanium $28, titanium ingot $40; the sheriff's revolver look is open (item art) | prices |
| P30 armour vs guns | fixed | armour stops at most 12 of 25 points against a round (P45; was 15) and every round of 2+ does at least half a heart; the shotgun hits harder (4 a pellet, tighter) | P30 armour vs guns |
| P31 hostages | fixed | townsfolk under threat from soldiers or monsters say raid lines, never "put that away" | towns hostage lines |
| P32 guns | fixed | rounds leave the controller aim ray in VR, hip spread halved; reload says why it can't start; G21: raising the Farsight to the eye zooms the view 4x inside a round lens, the dot where the round lands | P32 VR gun aim |
| P33 capital assault | fixed | inside the walls the alarm sounds at once, lockdown after 10 s (reinforcements); tower floors 1, 2, 4, 6 get a ring corridor with spokes and doors | basetest alarm, structcheck military_base |
| P34 capital food | fixed | Field Ration (fills 10 hunger, 16 saturation) in citadel supply and command chests | P34 ration |
| P35 floating pillars | fixed | capital portico columns reach down to the ground | structcheck capital_city |
| P36 radar blocks | fixed | a citadel console shows its patrols and garrison on the radar for 30 s | P36 console radar |
| P37 sheriff office | see G14 | | |
| P38 hunger | fixed with P12 | | P12 hunger |
| P39 lava | fixed | cave-floor lava pools kept; single lava sources sunk into cave floors (one floor cell in 100) | P39 lava |
| P40 capital ammo | fixed | Capital guns load Capital Rounds (never sold, looted from soldiers and citadels); rifle rounds $0.30, shells $0.40; Capital guns sold only in Capital cities | P40 ammo |
| P41 Elk Gulch stairs | open | the note's spot is solid rock in the current generator (the town moved), so the stairs could not be found; structcheck walkability is clean; needs the voice shot | |
| P42 potions | part | an original set of frontier tonics ("Quickstep Tonic", "Mending Tonic", "Black Draught"; docs/status/ip-renames.md); the doctor's rarer tonics turn up in only some shops; bottle art unchanged (he called the shop look "not bad") | P42 tonics |
| P43 gun accuracy | fixed | every gun but the shotgun hits exactly where the sights point | P32/P43 VR gun aim |
| P44 rarity | part | coal and iron rarer; Capital cities and citadels about one per 4,000 x 4,000 blocks on new ground; surface water unchanged (the lakes graph would seam saved worlds) | P44 rarity |
| P45 guns too easy in titanium | fixed | armour caps at 12 of 25 against a round | P30 armour vs guns |
| P46 endgame hordes | fixed | the Reckoning: back on the surface after the Ashguard falls, five waves (Marauder clans, the Capital, the Stormwarden Fleet with dropships, the dead, then every banner) close in from out of sight; a death sends the wave home to come again; winning pays $250 and ends Marauder patrols | P46 the Reckoning |
| P47 gunpowder upside down | fixed | dropped item icons drew upside down on both renderers | view --drop gunpowder |
| P48 base towns | fixed (new ground) | a row of shops (general store, saloon, gunsmith, doctor) and two houses below each citadel's south gate; the garrison leaves you alone there with empty hands, warns after a second with a weapon out and opens fire after four | P48 garrison row |
| P49 horses | part | mounting with a gun in hand; stamina half as long again; a monster beside the horse makes it shy briefly (no throw, none at a gallop) instead of rearing to a stop (the creeper and zombie notes); a swimming horse can jump and steps up onto a bank level with the water; ridden horses are narrower (squeeze between trunks); leaves at the rider's head stop the horse (no black screen); a dead horse already drops its saddle. Hoof sound on Capital stone not changed | P49 horses, horse stamina |
| P50 earned knowledge | fixed | a country's riches are told by a townsperson to a respected player (honour 20+), then shown on the map and at the border; before that only the name | honour gap P50 |
| P51 roads and riders | fixed (new ground) | dirt roads join neighbouring towns; riders on horseback travel them; a gun held on one for a second gets their satchel (cash and goods), which is a crime: honour, a bounty and a posse with six-irons from the nearest town; killing one is murder; the first bounty hunter carries a six-iron; dying with hunters or a posse on you pays every bounty off with all your cash | P51 roads and riders |
| P52 polygon world | done | on the Quest: Create New World > Terrain: Smooth (Test); an open world: Options > Video > Smooth Terrain (docs/status/polygon-test.md) | questcheck create path |
| P53 HUD | fixed | the Quest HUD rests at 45% and comes up solid for 4 s on a grip press or when hurt (VR Comfort > HUD Fade); in-game button prompts retire after 3 hours of play (Button Hints brings them back) | |
| P54 vehicles | prototype | the Vehicle Works block builds a preset Field Tank from a bill of parts (96 iron and the ship parts); the free build at a Helm stays; trade-off in docs/design/vehicles-p54.md | P54 vehicle works |
| P55 mob variety | fixed | each monster rolls its own speed (x0.8-1.25), hit (x0.7-1.4), toughness (x0.75-1.35) and archer aim | P55 mob variety |
| P56 VR reload | fixed | off hand at the hip takes a magazine, slotting it at the gun hand loads it; X still reloads | P56 VR reload |
| P57 bodies | fixed | bodies stay where they fell until the player is 48+ blocks away | mob anim P57 |
| P58 lines and time | fixed | closing-up and off-to-bed lines only in the evening; late at night the closed lines | P58/P59 night manners |
| P59 someone else's bed | fixed | sleeping in a town bed you didn't place costs 3 honour, once a night | P58/P59 night manners |
| P60 mob overlap | fixed | mobs are eased apart from each other and from the player | P60 no overlap |
| P61 hold A to count | fixed | hold A on a stack: items count onto the cursor, faster as you hold; a tap still takes the stack | padtest (Mac) |
| P62 town spacing | fixed (new ground) | 4 blocks between buildings along the street, deeper yards | P62 town spacing |
| P63 gunfire in town | fixed | the law within 48 blocks and the four nearest townsfolk within 32 walk over to look | P63 gunfire |
| P64 death and damage | fixed | experience is kept on death; bare skin takes a fifth more; deputies carry six-irons | towns |
| P65 clipping craft | fixed | crawlers break through buildings as they drive; dropships clear the tallest block under and ahead of the hull | |
| P66 drop craft | fixed | the cockpit is opened so the pilot sees out; it burns fuel (4 min) and refuels from coal or blaze rods | |
| P67 sheriff jobs marker | keep | works as he said | |
