# Sunderfall trailer v3a: blind review (Nov 14, 03:00 UTC)

Cut: `Sunderfall trailer v3a Nov 14.mp4` (45.2 s, 1920x1080, 13 shots, captions). It was rendered with the game's headless renderer from `docs/store/trailer-v3/shots.json` on branch claude/project-thread-2nosto (PR #730).

The story runs: a frontier world, then ride out, build, farm, the railway, the caves, outlaws come and you shoot back, the sky frigate's main gun, an enemy base, the war below, sunset, and the end card "Coming soon to Meta Quest / Wishlist now".

A fresh reviewer agent ran the video-review skill on it without being shown anything else. Its verdict was **NOT YET**. Its findings, most noticeable first:

1. The last-war soldiers still read as a WWII German army: field grey, flared steel helmets, armbands, collar tabs, a peaked cap, with the caption "the last war". **Fixed for v3b:** the Ashguard wear rounded visor helmets with ember lenses and no armbands or collar tabs (`BS_OLDASHLOOK=1` gives the old dress). The caption now reads "the war below".
2. It doesn't read as VR. It is a flat capture, and the controllers in hand are small and dark. **Partly addressed:** the hands are higher in view and every shot has hand work. This one is inherent to a flat trailer.
3. The rider sits in front of the saddle with his legs in the air. **Fixed:** the body faces the horse's way and sits on the saddle.
4. The build added a cobble skirt to a house that was already finished and walled up its door. **Fixed:** a plank wall and corner now go up from bare ground, with a doorway left open.
5. The strike had no visible cause, and the boom came 0.5 s before the fireball. **Fixed:** one shot, bow on, shows the gun charging and firing and then the blast, with the sound timed to the fireball.
6. The frigate was held 25 degrees nose down and read as a crash. **Fixed:** that side view is gone.
7. The tank hung over its own crater. **Fixed:** a smaller blast, and the shot ends sooner.
8. A dead outlaw lay draped over the gun. **Fixed:** the outlaws stop about 10 m out.
9. Other findings: the train caption said "Ride the rails" while you stand by the track (the caption is now "Steam trains cross the frontier"), the corridor guards walked away (they now come at you), and gold bits hung over the field (gone). Still open: held items read at a glance only as blocks, and the town has a modern tower.

Clean: captions, the end card, audio levels (-17.4 LUFS, peak -2.9 dBFS), and no other game's IP.
