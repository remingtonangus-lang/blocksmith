# VR melee and bow (Quest), Oct 10 redesign

Remington's long-standing #1 complaint: in Swing Mode the sword kept hitting things and breaking blocks wherever the
hand went while moving, with the trigger not pressed. Cause: any tip speed over 2.2 m/s counted as a "swing", and a
swing broke or attacked whatever the laser pointed at (no contact needed since Quest round 4).

## Rule: hand movement alone never does anything

Only the buttons mine, place, use and fire. The single exception is Swing melee: a blade that physically hits a mob
hurts that mob, and nothing else (`Game.interact`: a swing without a touched mob is ignored; it never mines, uses,
fires, or touches ship blocks).

## Two melee modes (VR Comfort & Controls > Melee)

- **Swing**: hit mobs by swinging a melee weapon (sword, axe, mace, trident, spear) into them. With a weapon in hand the
  right trigger mines and fires but never attacks a creature (`Game.meleeContactOnly`): aimed at one, the trigger does
  nothing (no attack, no mining past it); armor stands, boats and minecarts still take the trigger. Holding anything
  else (fist, blocks, torches, food, a bow) the trigger attacks as in Reclined.
- Friendly fire: a casual swing only hits hostiles (not tamed; neutral ones only once provoked). Villagers, townsfolk,
  golems, animals and pets take a blade hit only with the trigger held during the swing.
- **Reclined**: no swinging; the right trigger attacks what the laser picks (with the sword's aim assist) and mines, as
  before. Made for playing seated or lying back. Turning on the Reclined Mode posture also picks Reclined melee;
  turning it off restores the melee style from before (`QuestSettings.swingBeforeReclined`).
- Both: mining is automatic on the trigger with any tool; nothing needs to be hit physically.
- Saved setting: the old `quest.swingMode` key (on = Swing, off = Reclined), so old settings and `swingMode = off`
  overrides carry over.
- A melee weapon never mines while a hostile is within 6 blocks or any other creature within 3, in either mode
  (`Game.vrWeaponHeld`, `creatureNearForWeapon`): a cow 4 blocks off doesn't stop you digging.

## Blade contact (Sources/VRMelee.swift)

| | |
|---|---|
| Hit capsule | the drawn blade along the icon diagonal, x1.3 long (sword tip ~1.57 m from the hand), radius 0.25 m; fist 0.15 m, radius 0.15 |
| Sweep | the capsule from last frame's pose to this one, in sub-steps no farther apart than the radius (no tunnelling) |
| Min tip speed | 2.0 m/s relative to the head (walking, turning or a mob walking into a still blade is no hit); slower contact gives a light tick |
| Reach | contact point within 3.0 blocks of the eyes, in plain sight (`World.canSee`) |
| Once per swing | each mob once until the tip slows below 1.2 m/s |
| Damage | the normal attack charge (cooldown) x `VRMelee.power` = tip speed / 4 m/s, 0.7 ... 1.1: a charged swing deals what a trigger hit does |
| Feedback | haptic buzz 0.55 + 0.35 x power, crit sparks at the contact point, the mob's hurt flash; hurt yourself: a thump in both hands |

## Mob melee against the real body

Mobs measure their melee reach to `Game.meleeBody`: the column under the headset (`Game.vrHead`, at most 0.5 m from
the feet), on the Mac the feet. The numbers are unchanged (centre to centre under halfW + 1.3, within 2 blocks up or
down), so mobs are exactly as dangerous standing still; seated leaning back 35 cm dodges a zombie 1.4 blocks away,
leaning in gets hit by one 1.85 away.

## Bow (Sources/VRMelee.swift `VRBow`, QuestControls.bowUpdate / drawBow)

The bow is held in the aiming hand and drawn as solid geometry: upright limbs across the arrow, grip foremost, tips
bending back to the string (1.2 m bow, 0.15 m brace). The other hand's trigger at the string (within 0.3 m of the
resting nock) nocks an arrow; pulling back moves the string and arrow with the hand up to a full draw at 0.68 m from the
grip (only the hand's depth behind the grip counts, within 60 degrees of the rear axis: a hand ahead of the grip or out
to the side is no draw and no shot), with a haptic tick at every tenth of the draw (stronger and deeper as it bends) and a hum at full draw; the laser
runs along the arrow. Letting go of the trigger shoots from the bow along the arrow (from the drawing hand through the
grip) at draw x 60 b/s (`Game.vrBow`; a full draw crits). Dominant Hand: Left swaps the hands. A trigger pressed away
from the string shows a one-time hint.

## Testing

- Mac: `build/Blocksmith.app/Contents/MacOS/Blocksmith --snapshot /tmp/s.png --seed 12345 --find plains --time 0.3 --rd 4 --swingtest`
  (geometry, no tunnelling, reach, swings without contact, trigger never attacking in Swing, weapon mining guard, mob
  reach vs the leaning head, bow pose for both hands, the VR bow shot, options text fitting the pause menu).
- Quest sim (Linux CI, `quest/src/test/QuestSim.swift` `swingMelee`): fast air swings near a husk and walking with the
  sword break nothing; a fast blade swing hits a husk once with haptics; a slow touch and a husk out of reach don't; the
  bow nocks, draws (string at the hand, ramping haptics) and shoots along the arrow, right- and left-handed.
- Not verifiable off the headset: how the reach and capsule size feel, haptic strengths, the bow's look in the hand.
