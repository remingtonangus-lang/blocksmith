CUT = [
    # ACT I: THE HOOK & FRONTIER SANDBOX (main_title.m4a)
    ("hook_frigate_bow", 3.2, "One massive world — built for VR", [], {"xf": 0, "ss": 0.2}),
    ("fp_build",         3.4, "Build anything, block by block", [], {"xf": 0, "ss": 2.0, "speed": 1.5}),
    ("fp_farm",          2.8, "Work the land", [], {"xf": 0, "ss": 1.6, "speed": 1.25}),
    ("fp_ride",          3.2, "Saddle up and ride out", [], {"xf": 0, "ss": 0.4}),
    ("train_pass",       3.2, "Ride the rails across the frontier", [], {"xf": 0, "ss": 2.4}),
    ("town_life",        2.8, None, [], {"xf": 0, "ss": 0.5}),
    ("fp_cave_lush",     2.8, "Explore the caves below", [], {"xf": 0, "ss": 1.2}),

    # ACT II: SURFACE ESCALATION & SKY WARSHIP (ash_vault_battle.m4a drops at station_approach)
    ("station_approach", 2.6, "Infiltrate a base in the snow", [], {"xf": 0, "ss": 0.8}),
    ("station_breach",   2.2, None, [], {"xf": 0, "ss": 0.4}),
    ("outlaw_fight",     3.2, "Shoot it out with outlaws", [(0.25, "explodeLarge.wav", 0.9), (1.3, "explodeLarge_1.wav", 0.85), (2.5, "explodeLarge.wav", 0.95)], {"xf": 0, "ss": 0.1}),
    ("frigate_command",  2.8, "Command a warship in the sky", [], {"xf": 0, "ss": 0.4}),
    ("frigate_strike",   2.8, "and unleash its main gun", [(0.45, "explodeLarge.wav", 1.0), (0.50, "explodeLarge_1.wav", 1.0)], {"xf": 0, "ss": 0.1}),

    # ACT III: THE DEEP & THE LAST WAR
    ("hell_descent",     3.0, "Descend into the Deep", [], {"xf": 0, "ss": 0.3, "speed": 1.25}),
    ("ash_vault_war",    4.2, "and fight through the last war", [(2.1, "explodeLarge.wav", 1.0), (2.18, "explodeLarge_1.wav", 0.9)], {"xf": 0, "ss": 0.3}),
    ("sunset_finale",    3.3, None, [], {"xf": 0, "ss": 0.8}),
]
TITLE = 4.0       # ~49.5 s total runtime with end card
