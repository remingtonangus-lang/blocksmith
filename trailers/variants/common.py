def S(name, secs, cap, ss, sfx=()):
    # clips are already trimmed out of r11 at the shot's start, so ss only picks the r11 sound cues
    return (name, secs, cap, [(t - ss, f, g) for (t, f, g) in sfx if ss <= t < ss + secs], {"xf": 0, "ss": 0})
lava = [(0.8, "lavaPop.wav", 0.6), (2.0, "lavaPop_1.wav", 0.6), (3.0, "lavaPop.wav", 0.5)]
rocket = [(1.3, "gun_4.wav", 0.9), (1.6, "explodeLarge.wav", 1.0), (1.65, "debrisRain.wav", 0.7)]
SH = dict(
 vhook=lambda n="vhook_c": S(n, 3.5, None, 0.0),
 vride=lambda n="vride_c": S(n, 3.4, None, 0.0),
 coast=lambda: S("coast", 3.4, None, 0.0),
 flowers=lambda: S("flowers", 3.4, None, 0.5, [(1.0, "birdCall.wav", 0.5)]),
 vbuild=lambda n="vbuild_c": S(n, 3.6, None, 0.0, [(0.4, "place_wood.wav", 0.6), (1.3, "place_wood.wav", 0.6), (2.2, "place_wood.wav", 0.6), (3.1, "place_wood.wav", 0.6)]),
 lighthouse=lambda: S("lighthouse", 3.4, None, 0.2, [(0.3, "windGust.wav", 0.3)]),
 volcano=lambda: S("volcano", 3.2, None, 0.2, [(0.8, "lavaPop.wav", 0.5)]),
 cave=lambda: S("cave", 3.4, None, 0.9, lava),
 lava=lambda: S("lava", 3.0, None, 1.6, lava),
 vbase=lambda n="vbase_c": S(n, 2.8, None, 0.0, [(0.9, "gun_10.wav", 0.5)]),
 train=lambda: S("train", 3.0, None, 0.2),
 troops=lambda: S("troops", 2.6, None, 0.1, [(0.6, "gun_distant_0.wav", 0.5)]),
 dropship=lambda: S("dropship", 3.0, None, 0.1),
 battle=lambda: S("battle", 3.4, None, 0.1, [(0.5, "gun_distant_0.wav", 0.6), (1.6, "gun_10.wav", 0.35), (2.5, "gun_10_1.wav", 0.35)]),
 snowtank=lambda: S("snowtank", 3.0, None, 0.3),
 rocket=lambda: S("rocket", 3.4, None, 0.2, rocket),
 sunsetslow=lambda: S("sunsetslow", 3.2, None, 0.1),
)
TITLE = 4.5; SWITCH = "none"; FINALE = "sunsetslow"; CARD = ("COMING SOON TO META QUEST", "Wishlist now")
SH["vbuild"] = lambda n="realbuild_c": S(n, 3.6, None, 0.0, [(1.0, "place_wood.wav", 0.6), (2.4, "place_wood.wav", 0.6)])
SH["lava"] = lambda: S("emberlake_c", 3.0, None, 0.0, lava)
