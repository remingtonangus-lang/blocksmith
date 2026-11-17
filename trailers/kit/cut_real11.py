# Real-footage trailer r3: calm windows picked with motion.py (score <= ~4 per shot), slow-mo with in-between frames on
# the three shots that were too busy at speed, 60 fps output from the recorder's own frame times.
def S(name, secs, cap, ss, sfx=()):
    return (name, secs, cap, [(t - ss, f, g) for (t, f, g) in sfx if ss <= t < ss + secs], {"xf": 0, "ss": ss})

lava = [(0.8, "lavaPop.wav", 0.6), (2.0, "lavaPop_1.wav", 0.6), (3.0, "lavaPop.wav", 0.5)]
shell = [(0.45, "shipCannon.wav", 0.8), (0.9, "explodeLarge.wav", 1.0), (0.95, "debrisRain.wav", 0.6)]
rocket = [(1.3, "gun_4.wav", 0.9), (1.6, "explodeLarge.wav", 1.0), (1.65, "debrisRain.wav", 0.7)]

CUT = [
    S("vhook", 3.5, "Build, explore and fight in a VR sandbox", 0.0),
    S("vride", 3.4, None, 0.0),
    S("coast", 3.4, None, 0.0),
    S("flowers", 3.4, None, 0.5, [(1.0, "birdCall.wav", 0.5)]),
    S("vbuild", 3.6, "Build anything, block by block", 0.0, [(0.4, "place_wood.wav", 0.6), (1.3, "place_wood.wav", 0.6), (2.2, "place_wood.wav", 0.6), (3.1, "place_wood.wav", 0.6)]),
    S("lighthouse", 3.4, None, 0.2, [(0.3, "windGust.wav", 0.3)]),
    S("volcano", 3.2, None, 0.2, [(0.8, "lavaPop.wav", 0.5)]),
    S("cave", 3.4, None, 0.9, lava),
    S("lava", 3.0, "Descend into the Emberdeep", 1.6, lava),
    S("vbase", 2.8, "Raid enemy bases", 0.0, [(0.9, "gun_10.wav", 0.5)]),
    S("train", 3.0, None, 0.2),
    S("troops", 2.6, None, 0.1, [(0.6, "gun_distant_0.wav", 0.5)]),
    S("dropship", 3.0, None, 0.1),
    S("battle", 3.4, None, 0.1, [(0.5, "gun_distant_0.wav", 0.6), (1.6, "gun_10.wav", 0.35), (2.5, "gun_10_1.wav", 0.35)]),
    S("snowtank", 3.0, None, 0.3),
    S("rocket", 3.4, None, 0.2, rocket),
    S("sunsetslow", 3.8, None, 0.1),
]
TITLE = 4.5
SWITCH = "none"
FINALE = "sunsetslow"
CARD = ("COMING SOON TO META QUEST", "Wishlist now")
