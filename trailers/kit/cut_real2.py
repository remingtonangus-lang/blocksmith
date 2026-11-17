# Real-footage trailer cut list (tools/cine.py cut SEGDIR OUT.mp4 --cutlist cut_real.py --captions).
# Every shot is Remington's own Quest 3 headset recording from Nov 14 (rec-20261114-*), cropped to 16:9.
# Sounds are the game's own, placed on what happens on screen (blows, blocks, shells, blasts).
def S(name, secs, cap, ss, sfx=()):
    return (name, secs, cap, [(t - ss, f, g) for (t, f, g) in sfx if ss <= t < ss + secs], {"xf": 0, "ss": ss})

chop = [(0.1 + i * 0.27, f"hit_wood_{1 + i % 3}.wav", 0.7) for i in range(8)] + [(2.25, "break_wood.wav", 0.9)]
build = [(0.8, "place_wood.wav", 0.9), (2.8, "place_wood.wav", 0.9), (3.05, "place_wood.wav", 0.9), (5.0, "place_wood.wav", 0.9)]
fort = [(1.2, "gun_10.wav", 0.6), (1.9, "gun_10_1.wav", 0.6), (2.6, "gun_10_2.wav", 0.6), (3.6, "gun_10.wav", 0.6), (2.2, "gun_distant_0.wav", 0.5)]
ash = [(1.4, "shipCannon.wav", 0.8), (1.8, "explodeLarge.wav", 1.0), (1.85, "debrisRain.wav", 0.7)]
blasts = [(0.75, "explodeLarge_1.wav", 0.9), (1.7, "explode.wav", 0.8), (2.0, "explodeLarge_2.wav", 1.0), (2.05, "debrisRain.wav", 0.6)]
rocket = [(2.7, "gun_4.wav", 0.9), (3.0, "explodeLarge.wav", 1.0), (3.05, "debrisRain.wav", 0.7)]
lava = [(1.2, "lavaPop.wav", 0.7), (2.4, "lavaPop_1.wav", 0.7), (3.3, "lavaPop.wav", 0.6)]

CUT = [
    S("stilt", 3.8, "A world built for VR", 0.0, [(0.4, "windGust.wav", 0.5)]),
    S("coast", 3.4, "Fly its endless coasts", 0.5),
    S("flowers", 3.2, "Wander the wilds", 0.4, [(1.0, "birdCall.wav", 0.5)]),
    S("village", 3.6, "Find frontier villages", 0.3),
    S("build", 4.0, "Build block by block", 0.5, build),
    S("cave", 3.3, "Explore the caves below", 0.0, lava),
    S("lavalake", 2.8, "Find the Emberdeep beneath", 0.8, lava),
    S("snowtank", 2.2, "Face giant war machines", 2.0),
    S("ashtank2", 2.6, "Drive tanks into the Ash Vault", 1.0, [(t + 0.5, f, g) for (t, f, g) in ash]),
    S("rocket", 3.6, "Or blow it all up", 1.0, rocket),
    S("sunset", 3.4, None, 1.0),
]
TITLE = 4.5
SWITCH = "snowtank"
FINALE = "sunset"
CARD = ("COMING SOON TO META QUEST", "Wishlist now")
