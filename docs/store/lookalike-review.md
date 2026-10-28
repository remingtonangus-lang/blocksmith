# How close Sunderfall looks to the genre reference (P481)

_Written Oct 28 for Remington's question before the store submission ("Minecraft's what I'm worried about"). Not legal
advice: neither the lane nor the overseer is a lawyer. A lawyer's hour on the High items is worth it before launch._

## What can and can't be protected

Game rules and mechanics (mining blocks, crafting in a grid, hunger, a nine-slot hotbar, dimensions you reach through
portals) are generally not protected. The specific expression is: textures, character and mob designs, the look of the
user interface, logos, sounds and music, and distinctive structures and their art. A product can also be attacked on
"trade dress": a look so close that buyers could take it for the other product. Meta's content rules bar apps that
infringe someone else's IP, and a complaint after launch can pull the app. Names were handled already (the naming audit
in Sources/main.swift fails any reference name; docs/status/ip-renames.md).

## Findings, highest risk first

| Risk | What | Where it stands | Action |
|---|---|---|---|
| **High** | **Container screens** (inventory, chest, furnace, crafting table, anvil...). The panel was the reference's exact light grey (#C6C6C6) with its white/dark-grey bevel and black rim, at its exact 176 x 166 size; slots were its exact inset squares (#8B8B8B with #373737 and white edges) at its pixel positions, with a dark-grey title. This is the single most recognisable piece of its interface. | **Restyled in P481 part 1** (this PR): the Sunderfall look (worn leather-brown panel with a brass rim, rounded corners, dark recessed slots with a soft inner shadow, cream title). Slot positions stay (they are the grid mechanics). | Done; see it on the headset. |
| High | **Survival HUD**: ten heart icons in a row above the left of the hotbar, armour-shirt icons above them, a row of bubbles under water. P360 already redrew the hunger and experience bars. | **Redrawn in P481 part 1**: health, armour and air are slim segmented bars in the style P360 gave hunger (red health, gold absorption, a thin steel armour line, a thin blue air line). | Done. |
| High | **The player's figure** in the inventory (and wherever his body shows): a box head with a flat pixel face (two square eyes, a block mouth), box arms and legs: the reference's default player look in all but colour. | Changed in #585: a person's figure (slim limbs with gaps, a waist, hands, a modelled head on a neck with nose, ears, eyes, brows, lips and hair, like the townsfolk); worn pieces fitted to it. | Part 2: a modelled figure like the townsfolk (TownsfolkModel) and soldiers, which are our own. |
| Medium | **Crafting table top** (3 x 3 grid with tool icons), **TNT side** (red with a pale band), **grass block side** (dirt with a green fringe). The textures are our own paintings (128 px, painted style, not 16 px pixel art), but these three compositions echo the reference's most famous blocks. On the headset the ground is smooth polygons, so the grass side is rarely seen. | Our own art, familiar compositions. | **Repainted in P481 part 3**: the crafting table is a carpenter's bench on every face (long boards, bench-dog holes, a vise, drawers; no grid, no hanging saw and hammer); the explosive is a crate of blasting sticks (crate boards in an iron frame, a red disc with a black flame, a fuse coil on the lid). The grass side stays (rarely seen on the polygon ground). |
| Medium | **End-game set pieces**: the Hollow's floating island with obsidian spikes and a dragon circling, the twelve-socket portal frame filled with eyes, the end cities (purple towers with ships), the Emberdeep's fortresses and bastions, the Blight (three-headed boss). Layouts were built to match the reference's (Fortress, Bastion, Stronghold, EndCity, NetherGen). | Original names; the shapes and colours follow the reference closely. P360 already redesigned the desert temple. | Part 4 (larger): redesign the Hollow's look (no spikes ring and twelve-eye frame), the end-city towers and the Blight's silhouette. |
| Low | **Mobs.** The dead men (P185), skeletons, golems (P246), the Powderwight (a dead miner with a powder keg, not a green four-legged creature), the Voidwalker and the farm animals (FarmLooks) are our own designs. | Own designs. | None. |
| Low | **Terrain and blocks on the headset.** Smooth polygon ground, round trunks, 128 px painted textures. | Own look. | None. |
| Low | **Sound and music.** Synthesized in code or generated for Sunderfall (credits-and-licences.md); no reference audio. | Own. | None. |
| Low | **Logo, title, store art.** Sunderfall's own name and logo. Store pictures (P482) should show the polygon ground, towns, guns and ships, not a blocky inventory screen. | Own. | Pick store shots that show what is ours (art-plan.md). |

## What makes the case stronger

- Everything visible since the rename: no reference names anywhere (the audit fails a build that has one).
- The headset build looks unlike the reference: smooth ground, painted textures, original mobs, towns of people, guns,
  warships and armies.
- The store text should not compare the game to the reference by name.
