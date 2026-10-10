# The Deep expansion: full brief + expanded objectives (Remington + overseer, Oct 10)

DEEP EXPANSION (Remington, 10-10 14:42). The Deep exists (DeepGen/DeepSeam/EmberGen/AshWar/AshSites/AshUnits, ~1.7k lines) but is a first pass: you just dig straight through, the hell band is only 128 blocks and the Ash Vault is ~100 high. Make it a full endgame. Read the current code and docs first; extend, don't rewrite.
1. Hell (the Emberdeep band) must feel as big as the Nether: much taller open space with a sense of a sky/ceiling far overhead, varied biomes, lava seas, fortresses.
2. Hard gate below hell: below the hell band is a layer of an extremely hard rock that normal tools cannot break. The only way through is a rare ore found in bastion-equivalent strongholds in hell (guarded, next to a nether-portal-replacement structure). The raw ore must be processed (smelting plus a crafting step) into a tool or charge that can break the barrier. Make getting it a real fight.
3. The Ash Vault (the Ashguard: the WW2-German-styled army, keep the existing fictional names, no real insignia or swastikas, store-safe) becomes huge: an underground world with its own sky (high glowing ceiling, haze, day-like light), towns, bunkers, rail lines, airfields if feasible; tanks, halftracks, rifles, MGs, mortars, artillery, officers, patrols, alarms, reinforcements.
4. Difficulty: clearly harder than the modern military bases on the surface (more units, armour that needs explosives or the frigate-tier weapons, coordinated squads, AI that flanks and takes cover). Balance with a full-gear test run and document time-to-kill numbers.
5. Quest: keep it at 72 fps on Quest 3 (LOD, unit caps, fog); test both Mac and the Quest build check.
Fan out helpers per HEADER rules. Commit per item, update docs/status (new docs/status/deep.md), and list anything left for later.

EXPANDED OBJECTIVES (overseer, 10-10 14:45; meet these as well):
- Progression curve written down: what gear and level a player should have entering hell, reaching the barrier, and entering the Ash Vault; enemies and loot tuned to it.
- Each layer has its own ambient sound, music and lighting mood; a compass/map that still works underground; markers for the way back up.
- Ways back: lifts or shafts the player can build or unlock, so the trip isn't one-way; beds/respawn rules in the Deep documented.
- The barrier ore chain is in the recipe book with clear hints (a journal or a hell NPC hints where the strongholds are); the barrier break is a big moment (sound, light, falling debris).
- Bastion strongholds: 3+ layouts, guards with different roles, a mini-boss, loot vaults.
- Ash Vault story: journals, signs, radio chatter that tell who the Ashguard are; a rising alarm level as you push in.
- Vehicles: tanks and halftracks destructible with debris and fire, crew that bail out; mortars and artillery with audible incoming warnings so it is fair.
- AI: squads with roles (rifle, MG, officer, medic), cover use, flanking, retreat, calling armour; difficulty settings scale it.
- Boss: the Ash Marshal fight with phases and an arena; victory changes the Vault for good.
- Rewards unique to each layer (gear, blocks, trophies) and advancements for each milestone.
- Perf: unit caps, LOD and fog budgets measured on the Quest build in the biggest battle.
