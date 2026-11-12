# Store media candidates (updated Nov 12; none final until Remington picks)

Rendered in the cloud by the game's own Quest renderer (questcheck --cine, branch claude/project-thread-1q6065), his
world seed 7639458412018979794. No other game's names, logos or looks; no HUD; no real-world insignia.

- sunderfall_trailer_captions.mp4: 1920x1080, 30 fps, AAC audio. Story order: "One open world, built from blocks"
  (frontier town from above, its street, the Capital) / "Ride the rails across the frontier" / "or saddle up and ride
  out" (two riders on horseback) / "Build anything, block by block" / "Farm the land" (wheat and carrots growing, a
  farmer) / "Explore the caves below" (a lush cave lit by lanterns) / "Infiltrate a secret base in the snow" (air, gate, corridor) / "Shoot it out with outlaws" / "Command a
  warship in the sky" "and bring its main gun to bear" / "Then go deeper" (hell) / "and fight through the last war"
  (Ash Vault) / the town at sunset / title card.
- sunderfall_trailer_clean.mp4: the same without captions.
- covers/: brighter cover candidates, 2560x1440 (1 is the pick: the frigate over a frontier village at midday), plus
  square (1024x1024), portrait (1440x2560) and small landscape (1280x720) versions of the strongest two.
- screenshots/: 13 stills, 2560x1440 (drawn at 5120x2880, scaled down), daytime except the dusk town.
- clips/ (project files only): each shot on its own, 1920x1080, for re-editing.

Fixed after his Nov 11 notes and the 1000-frame dissection:
- Cracks: the village gables and wall corners showed sky through 1/16 slits where the realistic world's edge chamfer
  met stairs and slabs. Fixed in the mesher (no chamfer on a side a stair or slab closes whole); every village shot
  re-rendered and swept with the crack detector.
- The frigate: she stepped back every few frames (ships moved at 60 Hz under a 72 Hz camera) and drifted engine first
  (her own patrol AI overrode the cruise). She now moves every frame at the headset rate and flies bow first.
- "Ghost" buildings and slabs were cross-fades between shots: every cut is now a hard cut.
- Outlaw fight: the blasts no longer fell trees (felled trunks and leaves showed black in the sky).
- Snow base by day (its smoke showed black at night); the town opening at full daylight; the street walk no longer
  brushes the well roof or passes a townsperson in silhouette; the train now comes up the line close to camera.
- Gate: the striped band under the snow ledge is fixed in the game (PR #707, a texture off by one); the gate shot has its full approach again. Cabin: its footing goes two courses into the slope (a dark slot
  showed under it). Hell: framed off a pale ground patch. The cave and the tank shots are out of the cut.

Nov 12: the street shot re-rendered with the game's fix for the savanna well's corners (PR #706; the crack detector
finds no sky round the well now), and it starts a moment later, past a dark shape at the frame's edge.

Nov 12, after his notes on the 08:18 cut (13 s, 18 s, 32 s), 53.5 s now:
- 13 s, the "weird artifact before the house builds": the cabin opened on a lone footing strip; the shot now starts as
  the walls go up.
- 18 s, the "massive naval gun": the snow base spawned a full-size 42 cm capital turret on its roof (its deck plate,
  crates and a barrel past the fence). The game lane is swapping it for a light gun; until that lands the trailer's
  base shots leave it out. A parked dropship over the roof is hidden too. Grey puffs with "eyes" are fixed in the game.
- 32 s strobes: the main-gun blast's puffs reshuffle every frame and a dashed tracer flickers. The game lane has it;
  the strike is trimmed to 2.2 s until then.
- New: riding, farming and lush-cave shots (clips/ride, farm, cave_lush), so it isn't only bases and war.
