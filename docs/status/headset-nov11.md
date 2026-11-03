# What the headset must confirm (Remington back Nov 11)

Remington is away Nov 2 to Nov 11 with no Quest. Everything below was built and checked on the Linux host build
(questcheck) only. Each line says what to look at and what the host check showed, so a voice note can say yes or no.
The lane adds a line whenever it merges something the host can't fully prove. Newest at the bottom of each section.

## Frame rate (the store review, VRC.Quest.Performance.1)
- OVR Metrics, a few minutes each, in ordinary play: jungle, town, forest, taiga on foot. Host estimate (CPU only,
  host ms x 1.7): 0-0.09% missed frames (#652). GPU time can't be measured off the headset; his Oct notes put tree
  biomes under 60 on foot, so GPU time in jungle and forest with Auto View on is the main thing to read.
- The heavy scenes: driving the crawler, a citadel under fire, a naval fight, riding the train, Hell, an Ash Vault
  battle. Host estimate 0-0.46% missed (crawler the closest at 0.46%, citadel and naval 0.32%).
- Near the crawler: his Nov 1 note said the GPU maxed out beside it (P510). Host can't see GPU load.
- If all of these hold near 72, a new store build can go up as a Production draft for him to submit.

## Movement and controls
- The clamber: jump into a wall or crate stack 1-2 blocks over your feet and you pull yourself up and over (#648).
  Does it feel right? Does it fire when you didn't mean it to?
- Left grip: a quick tap steps the hotbar, also while bracing a gun (#648).
- Menu buttons are Large by default (#648).

## Vehicles
- The crawler: does the land round it draw while you drive (P511, #648-#650)? The interior (a motor at each wheel,
  hoists under the guns, bulkheads, fire control): better or still bad? Wheels wear and burst under rocket fire.
- The train (FAILURES 3): the line's ends now loop back into the line, so the train never stops at a "start".
- Garage door and elevator (FAILURES 1 and 2): rebuilt in #648.

## New to try (P512)
- The Proving Grounds: Worlds menu, "Proving Grounds (vehicles, circuits, guns)" (shown with Cheats & Commands on,
  as in playtest builds). The first load builds a deck high over the spawn a few steps a frame (you start flying while
  it goes down; "Proving Grounds" shows when it's done). On it: the hundred vehicles in rows by kind (boats afloat in
  channels), each with its helm and a sign; the hundred copper circuits on pads east of them; ten guns built from
  blocks to the north, each worked from the Command Console on its pad, facing a row of targets. Does the frame
  hold while it builds? Can you reach and use everything?
- Hired companions now ride the vehicle you drive when there's no free gun for them, and shoot their own guns from
  it. Hiring still costs $30 for a townsperson and $60 for a soldier: you said "a few thousand"; say if you want it
  raised and to what.
- Every gun on a frigate or crawler has a station inside the hull (a console with a chair) near its mount. On a hull
  you command, your companions sit at those stations and fire their guns while you drive. Only new hulls have the
  stations; one taken before keeps its old rooms.

## Fights
- Sheriffs on Hard: do they fight hard enough now (#648)?
- Void triangles (FAILURES 4): any left anywhere? Say where.
- Revenge raids (P512): a base you break or take is owed back about one time in four; 15-40 minutes later, when you
  are home, a dropship comes in and lands troops by your home. Before this fix the dropship and the sea hunters (corsair
  sloop, Corsair Cruiser) were made past the active distance and slept there, so none of them ever reached you. Does a
  raid reach your home now, and does a corsair come for you out at sea?
