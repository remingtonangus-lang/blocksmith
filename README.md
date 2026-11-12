# Store media candidates (updated Nov 11; none final until Remington picks)

Rendered in the cloud by the game's own Quest renderer (questcheck --cine, branch claude/project-thread-1q6065), his
world seed 7639458412018979794. No other game's names, logos or looks; no HUD; no real-world insignia.

- sunderfall_trailer_captions.mp4: 1920x1080, 30 fps, AAC audio. Story order: "One open world, built from blocks"
  (frontier town from above, its street, the Capital) / "Ride the rails across the frontier" / "Build anything, block
  by block" / "Infiltrate a secret base in the snow" (air, gate, corridor) / "Shoot it out with outlaws" / "Command a
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
- Gate: starts past a gap under the snow ledge. Cabin: its footing goes two courses into the slope (a dark slot
  showed under it). Hell: framed off a pale ground patch. The cave and the tank shots are out of the cut.

Known, passed to the game lane: small see-through wedges at the savanna village well's outer corners (its terracotta
ring is smoothed like natural ground), visible for a moment in the street shot.
