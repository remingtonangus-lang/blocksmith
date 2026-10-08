# Blocksmith round 4 (from Remington, Oct 8 2026)

Quest playtest of v0.66. Branch claude/quest-port; shared gameplay fixes also go to claude/blocksmith-playtest. Be lean: read docs/status/quest-port.md first, fix root causes, minimal diffs, no speculative refactors. Follow ~/.claude/CLAUDE.md (screenshot budget, batch greps, one blocking wait). Helpers: Opus 5.5 low or Haiku 5.5 only; never Sonnet, never Haiku 4.5, never Fable. Weekly usage is low until 10 PM tonight: commit after every item so nothing is lost if the run stalls.

## Capital / combat
1. Enemies spawn all around the Capital area, not concentrated in one spot.
2. Naval guns at the Capital base must be manned by an actual soldier. Today they auto-fire at the player even after everyone is killed and the player walks away. Gun fires only while a live gunner is on it; kill the gunner and it stops.
3. Big naval gun shells: flat, fast, direct fire (point and hit, minimal arc, howitzer/direct-fire feel). Shells currently pass through things: give them real collision with blocks, vehicles and entities.
4. Shell hits are devastating: one hit on a frigate takes out its engines and brings it down; shells tear apart crawlers near the base.
5. Crawler-vs-crawler damage much higher.
6. Frigate soldiers shoot through walls (player killed instantly after switching creative to survival with nobody near). Require line of sight and a sane range before they can fire.

## Vehicles
7. Dropships: commandeering must be obvious (clear prompt/marker) and boarding easier (bigger trigger zone, forgiving).
8. Walking on a moving or turning vehicle: player movement follows the vehicle's heading and feels random. Movement must be relative to the player's own head yaw, with the vehicle's motion just added on top.
9. Frigate must be drivable: add a findable helm/controls with an obvious prompt.

## Swing mode
10. Undo the "tool must physically touch the block" rule. Back to normal 6-block reach, with intent logic: prefer closer blocks over farther ones; when holding a sword, prefer entities/enemies over blocks.

## Spawning
11. Surface mobs were overcorrected: cut to 1/4 to 1/2 of the current rate.
12. Caves have far too many mobs (got swarmed by ~50). Cut sharply and add a local cap around the player.

## Quality of life
13. Controller pointer line sometimes disappears; it must always be visible.
14. Horse like RDR2: it follows you, and calling it brings it to you (spawns nearby) even from 2000+ blocks away.
15. No auto-pickup of junk items (flowers, vegetation, dirt). Picking them up needs a deliberate action (e.g. standing on / resting over them longer, or a press). Useful items still auto-pick up.
16. Sprint: the SPRINT tag shows but speed is the same. Make sprint actually faster (~1.3x) in all directions it applies to.

## Ship
Build (./build.sh fast while iterating), run relevant checks, commit, push, ONE blocking wait on Quest CI, confirm the APK on quest-dist. If `~/ClaudeTools/quest/platform-tools/adb devices` shows the Quest, install it. Update docs/status/quest-port.md with what changed. Then run:
~/ClaudeTools/voice/tell-remington "New Blocksmith Quest build is ready."
Do NOT start docs/requests/round3-features-after-reset.md.
