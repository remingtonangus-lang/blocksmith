# The code reader's Nov 10 batches

Remington's second reader goes through the code and reports what it finds; it never builds or runs anything, so each
finding is confirmed here first (by reading the code it names, or by a check), then fixed by intent ("the point is a game
good enough to sell"). Each fix has a `BS_OLD...` switch that puts the old behaviour back for before/after runs.
Checks: `questcheck --lookout` (1.1, also in the full suite), `questcheck --reader` (1.2, 1.3, 3.4), `questcheck --triptest`
(1.4). Proven fixes are also bug-ledger entries.

## Batch 1: freezes and stalls

| # | Finding | Confirmed | Fix | Proof |
|---|---------|-----------|-----|-------|
| 1.1 | A crewman's lookout search on a short hull built `a...b` with b < a: an endless loop on the headset (unchecked build), a trap on the host | Yes, by reading (CrewLookout y range `max(1, fy-1)...min(sy-2, fy+1)` on a grid 2-3 high) | `thru(lo, hi)` (Math.swift): an empty range when hi < lo. Swept: 97 loops of the same shape in 51 files (`BS_OLDLOOKOUT=1`) | --lookout, build 307: old still searching after 90 s, new 219 ms (ledger 69) |
| 1.2 | A big TNT stack drops the frame rate | Yes (TNTManager exploded every TNT due in one frame) | Past the first, blasts stop at 3 ms a frame and the rest go off on the next (`BS_OLDTNT=1`) | --reader, build 309: 2,000 TNT, worst tick 28 ms (58 over 13.9) old, 17 ms (2) new; 500: 11 and 8 ms (ledger 72) |
| 1.3 | A helm on a big building stalls about a second | Yes (assembly flood-filled every floor past the 60,000 limit) | The limit is checked per floor as it fills (`BS_OLDASSEMBLE=1`) | --reader, build 309: a helm against its wall 318 ms old, 18 ms new (ledger 71) |
| 1.4 | A Hollow rift loads its destination on the frame | Yes (gatewayTeleport called loadSync) | The rift arrival goes through the arrival hold (ledger 40) like every other trip (`BS_OLDRIFT=1`) | --triptest, build 307: the rift's tick 146-172 ms old, 8-10 ms new (ledger 70) |

## Batch 2: a buyer's first hour

| # | Finding | Confirmed | Fix |
|---|---------|-----------|-----|
| 2.1 | The first world is Creative | Yes (QuestApp's first load used an empty WorldRequest) | First launch opens a survival world |
| 2.2 | A grip held while moving throws the held item | Yes (the throw test used the hand's world speed, walking included) | The test uses the hand's own swing in the play space; the throw still carries his motion (`BS_OLDTHROW=1`). Touch matrix on build 314, carried 3.2 blocks at a sprint with the right grip held 0.3 s: the old test throws one (530 to 529), now kept (531 to 531) |
| 2.3 | Standing play: the world slides with a menu open | Yes (absorbHeadOffset ran with the body held) | With a menu open the view follows the head up to a metre; the body catches up once it closes (`BS_OLDMENUSLIDE=1`). Touch matrix, build 311: head 0.30 m aside, the eye moves 0.00 old, 0.30 now |
| 2.4 | Sitting down drops him into a sneak with no sign | Yes (a head 40 cm low counts as a duck) | A head held low and still for 3 s with the stick at rest is a seat: the view is raised to standing eye height until he stands (`BS_OLDSIT=1`). Touch matrix, build 311: head 0.6 m low for 4 s, old still sneaking with the eye at 0.72, now not sneaking at 1.62 |
| 2.5 | A quick Y press does nothing in survival | Yes (a tap only flies or calls a horse) | In survival with no horse a tap opens the inventory (`BS_OLDYTAP=1`) |
| 2.6 | The store APK has no libovrplatformloader.so: no entitlement check | Yes (nothing put it in the APK) | `STORE=1` builds set the store app ID and bundle the loader (quest/tools/fetch-ovrplatform.sh, Maven Central 77.0.1, checksummed); storecheck fails without either |
| 2.7 | The headset's exit saves don't call closeMenusForExit | Yes | Pause, session stop, the system's Quit and the quit-to-title save hand open screens back first (the pause menu stays) (`BS_OLDEXITSAVE=1`) |
| 2.8 | Restore Last Backup advised after any crash | Yes: the backup rolls back his pack and chests while the blocks stay, was offered in whichever world opened next, and the next save rotated it away | The session marker names its world; the offer is made only there, for ten minutes, with that world's backup kept meanwhile; the notice no longer advises it (`BS_OLDCRASHADVICE=1`) |
| 2.9 | A full disk may trap the save | Yes: FileHandle's old write and synchronizeFile have a try! inside on Android | Throwing calls, reported as a save problem; the hitch log, bug notes and voice notes appenders too (SaveIO.append) |
| 2.10 | The manifest lists quest2 and questpro | Yes | quest3, quest3s only |
| 2.11 | allowBackup is false | Yes | allowBackup true; the world mesh cache moved to the app's no_backup folder on the headset (it is rebuilt from the world and can be many MB) |

## Batch 3: vehicles and crew

| # | Finding | Confirmed | Fix |
|---|---------|-----------|-----|
| 3.1 | On a frigate he commands the crew never swing their guns | Yes (commandeeredTick cleared aimAt after gunCrewTick) | A gun a crew laid this update keeps its mark (`BS_OLDCREWAIM=1`) |
| 3.2 | The crawler's guns can't point lower than ~11 degrees | Yes (TankSight clamped wheeled hulls to -0.2...0.6) | Every gun keeps its own arcs; the crews too (`BS_OLDARCS=1`) |
| 3.3 | A use anywhere aboard the crawler or dropship takes the helm | Yes | A big kinematic hull's helm is taken at the helm (as P476's frigate); aboard, a use aimed at the hull's own blocks is for them (`BS_OLDCRAWLERUSE=1`) |
| 3.4 | A taken capital resets on every reload (chests refill, damage and his changes gone) and he may drop through her deck on load | Yes (only kind, pose and name were saved) | Her hull's cells (palette + lzfse), chests and turrets are saved and put back when she is built; the load holds him until she is (`BS_OLDTAKENGRID=1`). --reader, build 309: old, hole mended, turret back, chest refilled; new, all three kept (ledger 73) |
| 3.5 | Gun stations can't be filled or used | Partly. Crews engaged only within 110 of the hull's middle | Crews on a capital hull engage from her sides, enemy hulls out to 300 (`BS_OLDCREWREACH=1`). Left for his say: working a station himself, and the three-companion cap |
| 3.6 | Stormwarden crew leave their stations when he lets go of the helm | Yes (kept only within 24 of her middle) | Kept while he is aboard or within 24 of her hull (`BS_OLDGUNNERNEAR=1`) |
| 3.7 | The chase-view vignette closes on every hull turn | Yes (the chase offset's sweep counted as the view easing out) | Only the view easing out or in counts (`BS_OLDCHASEVIG=1`) |
| 3.8 | The crawler stops dead over a dip under its bow; water of any depth slows it | Yes (one column under the bow against one ahead) | A cliff is ground ahead 8 over where she stands across her bow's width; only water deeper than her draft slows her (`BS_OLDCRAWLERGROUND=1`) |
| 3.9 | A taken Stormwarden can't be patched, shows no hull %, keeps the slow reload | Yes (role checks said "frigate"; she is "warfrigate") | Her plans are drawn (Capital.frigate) and she gets the helm's quick reload (`BS_OLDPLANS=1`). Her speed is left as it is: his speed asks were made at the Meridian's helm |
| 3.10 | Patching the crawler rebuilds the rear ramp | Yes (the plans had it lowered) | Her plans have it raised |
| 3.11 | A copy of the reload clamp inside commandeerable() | Yes | Removed |
