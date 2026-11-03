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

## Fights
- Sheriffs on Hard: do they fight hard enough now (#648)?
- Void triangles (FAILURES 4): any left anywhere? Say where.
