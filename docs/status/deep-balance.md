# The Deep: balance and progression (gap pass DE1, D4b)

Numbers come from `questcheck --deep-only` (DeepGapTests.balance). Each duel is seeded, so a run gives the same
numbers until the code changes. The player stands still in full Duskium armour (the best a player can wear at the
vault) on normal difficulty. "Kills you" is how long the unit takes to deal 20 health (10 hearts) of damage through that armour; the player is
healed every tick, so this is a damage rate, not a staged fight.
"You kill it" is how long the player takes holding the trigger with the named weapon, aimed at the unit's middle,
with the unit held where it stands (it still turns and fires): a pure damage race.
Standing still is the worst case: a moving player takes far less fire.

## Time to kill (2026-10-11)

| Unit | Kills you | You kill it | Weapon |
|---|---|---|---|
| Capital rifleman (surface, for scale) | 39.0 s | 2.8 s | Capital Service Rifle |
| Blight Skeleton (hell band; now its heir, the Brand Knight) | 5.4 s | 3.2 s | Capital Service Rifle |
| Boarling Brute (hell band; now its heir, the Brand Champion) | 2.5 s | 4.7 s | Capital Service Rifle |
| Keep Castellan (mini-boss) | 2.7 s | 24.4 s | Capital Service Rifle |
| Ashguard Rifleman | 12.3 s | 4.0 s | Capital Service Rifle |
| Ashguard Stormer | 52.5 s | 8.0 s | Capital Service Rifle |
| Ashguard Heavy | 7.4 s | 20.6 s | Capital Service Rifle |
| Ashguard Half-track | 32.5 s | 12.4 s | Skybreaker Launcher |
| Cinder Tank | 17.6 s | over 60 s | Capital Service Rifle |
| Cinder Tank | 12.2 s | 28.5 s | Skybreaker Launcher |
| The Ash Marshal (alone, no guard) | 4.2 s | 84.6 s | Skybreaker Launcher |

The check enforces five things:
- The Ashguard rifleman is harder than a surface one round for round: each round he fires takes more than twice what
  a Capital rifleman's does. (It no longer takes longer to kill: since P358 any soldier drops to two rifle rounds to the
  body or one to the head. Nor does he kill faster through full gear: six in ten carry the Kessel bolt rifle, one heavy
  round a second against the Donnerkeil's eight, P499.)
- A Cinder Tank shrugs off rifles: their rounds do a fifth of their damage on its plate, so bring a launcher.
- Every unit can be beaten with full gear: the Marshal within 180 s, everything else within 60 s.
- Nothing kills a full-gear player in under 2 s.
- Melee monsters (the Brute, the Castellan) kill fastest standing still. Their counter is distance; rifles outrange them.

Tuning made in the gap pass:
- Ashguard soldiers are veterans: 75 % more health (60 % before the gap pass), 60 % more gun damage and a 40 % tighter
  group than the same rank on the surface.
- The Cinder Tank's plate cuts bullet damage to 20 %.

## Progression curve

| Stage | Expected gear | What it takes |
|---|---|---|
| Surface to the Emberdeep | Iron to diamond, bow, first guns | Emberdeep fortresses and bastions as usual |
| Into the hell band (Deep, internal y 200-375) | Diamond to Duskium, rifle, fire resistance | Blight Skeletons and Brutes kill in 2-6 s standing: fight at range. Keeps hold the Sunderite and the Castellan (24 s of rifle fire) |
| At the seal (y 192-199) | Duskium plus a Sunderite Pickaxe or Sunder Charge from keep ore | No enemy: only Sunderite breaks Sealrock. The break drops a Sealrock Shard |
| Into the Ash Vault | Full Duskium, rifle and launcher, healing | Riflemen 4 s each, Heavies 17 s, armour needs the launcher. Squads of 3-6 arrive at Alarm, armour joins at Total War |
| The Marshal | Launcher, cover, keep moving (marked barrages) | About 85 s of launcher fire alone, plus two guard calls. Drops the Marshal's Cap, a helmet a little better than Duskium |

Rewards along the curve (DE13): the Castellan's Brand and a Gate Shard (hell band), the Sealrock Shard (seal), the
Marshal's Cap, a wearable helmet (vault). Each milestone has an advancement. The trophies drop once, whatever the
Looting. The first Ashguard officer you kill carries a Keeper's Journal.
