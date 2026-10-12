# C3 your own nation (2026-10-12)

What shipped (Sources/Nation.swift; check: `questcheck --nation-only`, Sources/NationTests.swift):

- **Provinces.** Every town you take (TownConquest) and every Greywall base you take is a province of your nation.
- **The council.** Ring the bell in one of your towns: name the nation, pick its flag colour, set taxes (low, fair,
  high), pass or repeal laws (curfew, conscription, open market), name this town your capital and choose the style of
  its hall (timber, stone, brick). It lists every province with its settlers, garrison, buildings and loyalty, and the
  latest news.
- **Days.** Simulated from the save (days away count, up to 30 at once). Loyalty drifts toward 55; low taxes +3 a day,
  high -4; curfew -1.5, conscription -1, open market +1; the capital +2 and +1 once its hall stands.
- **Settlers.** A loyal province (35+) draws one or two settlers a day (16 in a town, 8 at a base). Every three build:
  a fenced wheat farm with water or a cabin, on open level ground 30-60 blocks round the town; the capital's hall
  (13 x 13, flag in your colour on a pole) once six have come. Built when you're near. Up to six settlers walk the town
  as its folk. Each settler adds $0.50 to the day's tribute; taxes scale it (x0.5, x1, x1.6), the market adds 15%.
- **Defending.** About one day in twelve a province is raided while you're away (curfew halves it): garrison,
  buildings and loyalty against the raiders. Held: loyalty +3. Lost: loyalty -12, a quarter of the settlers leave.
  While you're there the night raids come to your towns twice as often; beating one off is +10 loyalty.
- **Revolt.** A town under 15 loyalty for three days throws you out. Bases hold (the garrison is yours).
- **Map.** Provinces show on the world map in the flag colour, the capital larger with a star.

Defaults picked (no questions asked): the bell is the council (no new block); settlers build from fixed small plans
rather than designing; "a capital you design" is the name, flag, hall style and whatever you build there yourself.

Leftovers (not built): settlers walking out to farm the plots they built (they stroll the town), raiders you can see
attacking a province while you're away, a province border drawn on the map, settlers at bases.
