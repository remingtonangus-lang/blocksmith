# The first hour teaches itself (P402)

A new player gets no tips (NO TEXT), so the world has to show what to do. This is what a new survival player must find
out in the first hour, and what shows it in the world.

| What to find out | How the world shows it |
|---|---|
| Gather wood | The spawn camp sits 4 blocks ahead of the first view, turned toward the nearest tree. When that tree is more than 7 blocks off, torches every 4 blocks lead to it. The chest holds a wooden axe. The lean-to's frame is logs and planks. |
| Craft | A workbench stands beside the campfire. Using it opens the crafting screen, and the Goals line (a bare name) asks for one next. |
| The crafting menu | The same workbench. Pressing Y for the inventory shows the 2x2 grid too, and the left controller's Y picture on the loading screen is a chest. |
| Shelter | The broken lean-to (two log posts, one fallen short, and a plank or two of its roof) shows that wood builds shelter. Goals ask for "A Night's Sleep". |
| Food | The camp chest holds 3 bread. Farm animals spawn on grass round the spawn as before. |
| The first ore | Goals ask for Stone, then the Stone Pickaxe. The chest's wooden pickaxe digs stone. Ore shows in cave mouths and cliffs as before. |
| Night danger | The campfire burns at the camp all night (light 15, smoke by day), the first safe place to come back to. The torches along the path stay lit too. |
| The controls | The loading screen shows both controllers, each control tinted and joined by a line to a pixel picture of what it does (no words). On the right controller: the trigger mines, the stick turns, B goes back, A jumps and the grip steps the hotbar on. On the left: the trigger places, the stick walks, Y opens the inventory, X picks the block aimed at and the grip steps the hotbar back. Dominant Hand Left swaps the pictures. The controller card (look at a controller in your hand) is unchanged. |
| Voice notes | Not in store builds. STORE=1 leaves out the recorder and the cloud planner (P396), and storecheck.sh proves it. |

## Comfort (step 4)

A new profile starts on the Moderate comfort preset (QuestSettings defaults; QuestOptions.comfortPreset reads them as
Moderate):
- snap turns of 45 degrees, no smooth turning
- a 0.6 vignette while moving, turning, riding horses, sailing or piloting ships, and in jet flight
- the steady saddle
- reduced knockback

docs/store/comfort-rating.md now says this.

## Shots (step 5)

- `questcheck --view OUT.png --field --scene spawncamp --look 0,-15` shows the spawn camp of a new world.
- `questcheck --controllerpic OUT.svg` writes the loading screen's controller picture.
