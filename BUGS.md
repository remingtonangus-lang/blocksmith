# Bug classes

Each class: what goes wrong, the oracle that catches it (machine, not a human), instances, the fix, status.
Status: open (oracle finds instances), fixed (oracle at 0 on CI, check made strict), watching (fixed, not strict yet).

| Class | Oracle | Instances | Fix | Status |
|---|---|---|---|---|
| Village house floors a block above the door sill (must jump in; beds, tables, villager spawns set into the floor) | `--structcheck` door_step, mob_in_block; `--agent village` goal | every village house (Remington, playtest) | pending: floor at the sill level | open |
| Villagers acting weird | `--agent village`, behaviour sim (planned) | Remington, playtest | pending | open |
| Far ocean showed the sky through the water (LOD 1 dropped unlit seabed faces) | tour_777_aerial visual check | seed 777 | Mesher keeps faces into water / sections with water at LOD 1 (1d894fa) | watching |
| Explosions destroyed the Blight Star | playthrough "Blight Star drops and is picked up" | 1 (run 338) | star survives blasts (ca7df81) | watching |
| Kelp / seagrass out of water | `--kelpcheck` | 0 kelp; seagrass in 1-deep shallows only | - | fixed |
| Build breaks only a compiler would catch (unbalanced braces) | tools/precheck.py (pre-push) | 1 (run 340) | precheck before every push | fixed |
| Expressions that time out the Mac's type checker | CI type-check gate (>= 600 ms) | ~35 split so far | typed lets, plain loops | watching |
