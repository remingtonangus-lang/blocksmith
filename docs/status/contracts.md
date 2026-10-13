# C11 jobs and contracts (2026-10-13)

What shipped (Sources/Contracts.swift; check: `questcheck --contracts-only`, Sources/ContractsTests.swift):

- **Where.** Every town's notice board posts two contracts a day under its two daily jobs (TownBoard: deliveries,
  hunts, outlaws). The map table of a Greywall base you hold opens the quartermaster's contracts (camps and couriers),
  with the war report as its last row. A town in a country posts for that country.
- **Courier.** A sealed parcel to another town 500-1,500 blocks off; paid when you walk into that town with it.
- **Escort.** A traveller follows you to another town; road agents wait past half way; paid when they arrive alive,
  and they settle there. A dead traveller ends the contract.
- **Clear a camp.** A bandit camp 120-220 blocks out (a campfire and four or five bandits) appears as you near it;
  clear it and collect at the board.
- **Defend the town.** Be in town after dark: the raiders come; beat them off and you're paid.
- **Pay.** Dollars and honour; a town in a country also raises your standing with it (+3). Contracts not done in
  three days lapse.

Leftovers (not built): contract markers on the map, an escort on horseback or by wagon, bounty contracts against named
gang leaders with their own hideouts (the outlaw job covers bounties today).
