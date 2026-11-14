# Sunderfall trailer v3e: blind review (Nov 14, morning)

Cut: `Sunderfall trailer v3e Nov 14.mp4` (41.4 s, 1080p, 11 shots, captions). It was rendered with the game's headless renderer from `docs/store/trailer-v3/shots.json` on branch claude/project-thread-2nosto.

Overnight there were five cuts (v3a to v3e). After each cut, a fresh reviewer agent watched it blind with the video-review skill. The verdict is still **NOT YET**, so a v3f is being built now.

## Fixed since v3a

- **Soldiers in the war shot.** They no longer read as a WWII German army: the troopers are out of that shot, and the Ashguard wear visor helmets with no armbands.
- **Outlaw leader.** No longer in a black uniform; he now wears a brown duster.
- **Hands.** There are gloved hands with knuckles, a thumb and a shirt sleeve, where before there was a grey controller block. When you build, the hand reaches out and points its laser at each block.
- **Horse ride.** Shot in first person: you see the horse's head and neck, with no rider floating off the saddle.
- **Building.** A plank wall with a doorway goes up from bare ground, close to the camera.
- **Frigate main gun.** Shot from the deck behind the gun: it charges, fires a beam, and the blast lands. There is no outside camera and the ship is no longer scorched by its own shot.
- **Town.** The town shots moved to the timber village, so there are no modern towers.
- **Other fixes:** tracer bars, wheat bits, the corpse on the gun, the tank hanging over its crater, and leaves in the camera are all gone.

## Still open in v3e (v3f addresses the first three)

1. The farm shot shows a dark "blade" sweeping through the camera. The cause was a tree that the staged field cut, falling across the view; it also made the "sheared leaf tarp". v3f removes felled trees from staged shots.
2. The outlaws came out of the town, so the fight read as attacking it. In v3f they come across the open field, toward you and a townsman with a pitchfork.
3. The cave lantern read as a box. v3f gives the player a torch.
4. It still doesn't fully read as VR: the hands don't grab or reload. This is the reviewer's top point every round.
5. Smaller points:
   - The frigate gun fires at empty forest.
   - The tanks in the Deep don't move.
   - The train has no steam.
   - Smoke and muzzle flashes are pixel sprites.
   - The textures on cave ledge sides are smeared.
   - One outlaw floats when hit.

Clean: captions, the end card ("Coming soon to Meta Quest / Wishlist now"), audio levels, and no other game's IP.
