# Playtest — Oct 9 afternoon (Quest, v80) — Remington, typed from voice

Much of it played well. These are IN ADDITION to everything already queued; nothing here replaces existing work.

1. Horse up hills is choppy — every block step jolts the view, close to motion sickness. Mounted movement over 1-block steps must be smooth (the step-up eased over time for rider and camera, never snapped). Comfort bug: top priority.
2. Horse legs look detached when walking or when hit (gaps at the joints / pieces separating). Fix the model and animation so limbs stay attached in every pose and on hurt.
3. Too much vegetation. Grass: try about 1/8 of the current amount (this morning's cut wasn't enough). Cactus far too common. Review all plants for density.
4. Surface mob density: about half of what it is now. Keep this morning's cave spawning working.
5. Copper (our redstone) needs full feature parity with Minecraft redstone, so a player coming from Minecraft doesn't have to relearn: every component and behaviour (dust/wire, torches, repeaters, comparators, observers, pistons/sticky, hoppers, droppers/dispensers, daylight sensors, pressure plates, buttons, levers, tripwire, target block, note block, lamps, rails, quasi-connectivity if feasible). Make a parity checklist with a working test for each item.
6. Crafting stations: Remington asked whether "the workshops have to change workbenches" or whether one stone bench works. Answer it plainly in the report: list every crafting station, what each one is needed for, and whether any recipe needs a station a Minecraft player wouldn't expect.
7. Bone meal doesn't work on sugar cane (and probably other plants). Audit every plant and make bone meal work wherever it does in Minecraft Bedrock (sugar cane included). Getting paper was a grind.
8. Cow leather: slightly more common / a bit more per drop.
9. Enchanting table: an enchant should sometimes add extra enchantments (several at once at higher levels). Remington only saw Efficiency and Unbreaking for the pickaxe. Fortune and Silk Touch already exist in code, so check the table offers them and that offers vary properly.
10. Store / IP: check every name for Mojang-coined words (e.g. sculk, netherite, Nether, Ender-anything, Silk Touch, Bane of Arthropods, Riptide, Swift Sneak, Soul Speed, Frost Walker…) and rename those to our own. Common English words (Efficiency, Fortune, Unbreaking, Sharpness) are fine. List every rename in docs/status/ip-renames.md. Not legal advice: flag anything unsure for Remington.
11. Render distance still has to meet the performance gate (STORE_QUALITY.md).
12. Voice bug notes (always-on recorder): see the voice-bug-notes task. Huge priority for Remington.

Big idea, under consideration (prototype only, separate task): a smooth/polygonal natural environment. Keep crafted and functional things as blocks; make terrain and natural materials look organic; breaking chips off small polygon pieces.
