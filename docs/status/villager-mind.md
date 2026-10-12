# C4 villager minds, the placeholder (2026-10-12)

What shipped (Sources/VillagerMind.swift; check: `questcheck --mind-only`, Sources/VillagerMindTests.swift):

- **The interface.** `VillagerMind` answers three questions for a townsperson: the greeting (Game.townGreet's last word,
  after conquest, anger, honour and voiced lines), an opinion of the player (hates ... admires, from reputation,
  honour and whether you hold the town) and the day's choice (Mob.activity). `VillagerContext` is what a mind sees:
  name, role, profession, town, time of day, reputation, honour, the player's name, whether you hold the town, a raid,
  hostility, child or adult.
- **ScriptedMind** (the default) is today's behaviour, unchanged: the written greeting tables, the schedule
  (`Mob.scriptedActivity`) and the reputation scale.
- **ModelMind** is the stub a small model will drive. It builds a short prompt from the context, hands it to a
  `MindBackend` off the frame thread, cleans the answer (one line, 2-90 printable characters) and uses it the next time
  that villager greets you or plans (a plan holds for an in-game hour). Before an answer arrives, with an unusable
  answer, or with no backend, every call falls back to ScriptedMind. Sheriffs, deputies, shopkeepers and bankers keep
  the scripted schedule whatever the mind (shop hours and patrols are game rules).
- **No model yet.** `VillagerMinds.probe()` returns nil everywhere, so the game runs the scripted mind. The backend
  to add: Apple Foundation Models on the Mac (`LanguageModelSession`, macOS 26), the Quest's NPU later; each is one
  `MindBackend` class returned from `probe()`.
