# Real-footage trailer r3: calm windows picked with motion.py (score <= ~4 per shot), slow-mo with in-between frames on
# the three shots that were too busy at speed, 60 fps output from the recorder's own frame times.
def S(name, secs, cap, ss, sfx=()):
    return (name, secs, cap, [(t - ss, f, g) for (t, f, g) in sfx if ss <= t < ss + secs], {"xf": 0, "ss": ss})

lava = [(0.8, "lavaPop.wav", 0.6), (2.0, "lavaPop_1.wav", 0.6), (3.0, "lavaPop.wav", 0.5)]
shell = [(0.45, "shipCannon.wav", 0.8), (0.9, "explodeLarge.wav", 1.0), (0.95, "debrisRain.wav", 0.6)]
rocket = [(1.3, "gun_4.wav", 0.9), (1.6, "explodeLarge.wav", 1.0), (1.65, "debrisRain.wav", 0.7)]

CUT = [
    S("stilt", 3.6, "A world built for VR", 0.3, [(0.6, "windGust.wav", 0.4)]),
    S("flowers", 3.4, "Wander the wilds", 0.5, [(1.0, "birdCall.wav", 0.5)]),
    S("wildlife", 3.0, "Meet its wildlife", 0.3),
    S("build", 3.4, "Build it block by block", 0.2),
    S("cave", 3.4, "Explore the caves below", 0.9, lava),
    S("lava", 3.0, "Find the Emberdeep beneath", 1.6, lava),
    S("snowtank", 3.0, "Face giant war machines", 0.3),
    S("ashshell", 3.2, "Drive tanks into the Ash Vault", 0.2, shell),
    S("rocket", 3.4, "Or blow it all up", 0.2, rocket),
    S("sunset", 3.6, None, 0.3),
]
TITLE = 4.5
SWITCH = "snowtank"
FINALE = "sunset"
CARD = ("COMING SOON TO META QUEST", "Wishlist now")
