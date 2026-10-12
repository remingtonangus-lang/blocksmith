# C9 seasons (2026-10-12)

What shipped (Sources/Seasons.swift; check: `questcheck --seasons-only`, Sources/SeasonsTests.swift):

- **The year.** Four seasons of seven days, spring first (day 1 of every world is the first day of spring). Everything
  follows the day count: saves need nothing new. A toast marks each season; the world map's info line shows the
  season and the day in it.
- **Weather.** The season shifts every biome's temperature (spring -0.1, summer +0.2, autumn -0.15, winter -0.7). In
  winter snow falls instead of rain over the plains, forests and swamps, settles on the ground and on the treetops,
  and lakes freeze from the shore. From spring the seasonal snow and ice melt again (never in biomes cold all year).
- **Crops.** 1.2x in spring, 1.5x in summer, 1x in autumn; out in the open they stop in winter, a roofed field grows at
  half speed. Shops pay 30% more for crops in winter and 15% less at the harvest (summer, autumn).
- **Animals.** A third as many turn up in winter outside the warm biomes; in autumn the herds drift south, in spring
  back north.
- **Hunting seasons.** Autumn and winter are the open season: pelts sell 40% dearer. Killing game in spring within 300
  blocks of a town costs honour (-2, "hunting out of season").
- **Festivals.** The third day of each season: Spring Fair, Midsummer Fair, Harvest Festival, Winter Lights.
  Townsfolk gather at the bell all day, shops take 10% off, and at night fireworks go up over the square while
  you're in town.

Defaults picked: snow on trees is the existing snow layer settling on leaves (no new tree look; tree looks are the Mac
worker's); "migrate" is herds drifting a couple of dozen blocks at a time, not long-range herds.

Leftovers (not built): festival stalls and decorations, frozen rivers you can cross on horseback being called out on
the map, seasonal leaf colours (a tree look: the Mac worker's).
