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
| P18 water falling one block | open | | |
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
| P30 armour vs guns | fixed | armour stops at most 15 of 25 points against a round and every round of 2+ does at least half a heart; the shotgun hits harder (4 a pellet, tighter) | P30 armour vs guns |
| P31 hostages | fixed | townsfolk under threat from soldiers or monsters say raid lines, never "put that away" | towns hostage lines |
| P32 guns | part | rounds leave the controller aim ray in VR, hip spread halved; reload says why it can't start; the Farsight scope is G21 | P32 VR gun aim |
| P33 capital assault | fixed | inside the walls the alarm sounds at once, lockdown after 10 s (reinforcements); tower floors 1, 2, 4, 6 get a ring corridor with spokes and doors | basetest alarm, structcheck military_base |
| P34 capital food | fixed | Field Ration (fills 10 hunger, 16 saturation) in citadel supply and command chests | P34 ration |
| P35 floating pillars | fixed | capital portico columns reach down to the ground | structcheck capital_city |
| P36 radar blocks | fixed | a citadel console shows its patrols and garrison on the radar for 30 s | P36 console radar |
| P37 sheriff office | see G14 | | |
| P38 hunger | fixed with P12 | | P12 hunger |
