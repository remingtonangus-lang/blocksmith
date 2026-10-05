"""Lever-action repeaters: Merriman Repeater (24" octagonal barrel, brass receiver, crescent butt) and Harlan
Saddle Carbine (20" round barrel, case-hardened receiver, barrel bands, saddle ring). Original designs built on the
period toggle-link lever mechanism: lever loop, sliding bolt that protrudes when open, side loading gate, top
ejection, full-length tube magazine."""
import math

import numpy as np
from scipy.spatial import ConvexHull

import gun_lib as L
from gun_rig import FINISHES, Gun

FINISHES["merriman_lever"] = {
    "standard": {"frame": "brass", "barrel": "blued", "tube": "blued", "hammer": "case", "lever": "blued",
                 "small": "blued", "bolt": "steel", "butt": "brass", "cap": "brass", "wood": "walnut",
                 "fore": "walnut_fore", "sight": "blued"},
}
FINISHES["harlan_carbine"] = {
    "standard": {"frame": "case", "barrel": "blued", "tube": "blued", "hammer": "case", "lever": "case",
                 "small": "blued", "bolt": "steel", "butt": "blued", "cap": "blued", "wood": "walnut",
                 "fore": "walnut_fore", "sight": "blued", "ring": "iron"},
}


def _hull(circles, n=20):
    pts = []
    for (cx, cz, r) in circles:
        for i in range(n):
            a = math.tau * i / n
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    hv = ConvexHull(pts).vertices
    return [pts[i] for i in hv]


def _wood(name, outline, hw, kind, round_r, cut_polys, step=0.004):
    """Pillow-shaped wood part, then cut flat where it meets steel (polygons in YZ, extruded through X)."""
    o = L.pillow(name, outline, hw, kind, round_r=round_r, step=step)
    cutters = [L.extrude("cut", p, -0.05, 0.05, "blued", bev=0) for p in cut_polys]
    if cutters:
        L.boolean(o, cutters)
    L.finish(o, math.radians(60))
    return o


def build_lever(g: Gun, carbine=False):
    k = g.k
    BL = 0.508 if carbine else 0.620               # barrel length from the receiver face
    RY0 = -0.150                                   # receiver rear
    TOP = 0.0145
    BOT = -0.034
    W = 0.0128
    TZ = -0.0200                                   # magazine tube axis
    # ---------------- receiver
    prof = [(0.0, -0.0300, 0.004), (0.0, 0.0110, 0.003), (-0.0060, TOP, 0.004), (-0.1250, TOP, 0.012),
            (RY0, 0.0060, 0.006), (RY0 - 0.003, -0.0230, 0.006), (RY0 + 0.010, BOT, 0.008), (-0.0120, BOT, 0.010)]
    rec = L.extrude("receiver", prof, -W, W, k("frame"), bev=0.0008, bseg=2)
    port = L.box("port", -0.0062, 0.0062, -0.1140, -0.0480, 0.0040, 0.03, "blued", bev=0)
    boltway = L.box("boltway", -0.0058, 0.0058, -0.165, -0.110, -0.0064, 0.0098, "blued", bev=0)
    hslot = L.box("hslot", -0.0049, 0.0049, -0.158, -0.128, -0.026, 0.03, "blued", bev=0)
    lslot = L.box("lslot", -0.0060, 0.0060, -0.135, -0.004, BOT - 0.01, BOT + 0.0045, "blued", bev=0)
    L.boolean(rec, [port, boltway, hslot, lslot])
    L.bevel(rec, 0.0004, 1, 40)
    L.finish(rec)
    g.add(rec)
    # side plate seams + receiver screws
    for sx, ax in ((W + 0.0001, "x+"), (-W - 0.0001, "x-")):
        g.add(L.screw("sp1", (sx, -0.088, -0.014), ax, 0.0028, k("small"), slot_angle=20 if sx > 0 else 70))
        g.add(L.screw("sp2", (sx, -0.034, 0.002), ax, 0.0024, k("small"), slot_angle=110 if sx > 0 else 35))
        g.add(L.screw("hs", (sx, -0.1470, -0.0200), ax, 0.0026, k("small"), slot_angle=80 if sx > 0 else 10))
        g.add(L.screw("ls", (sx, -0.0180, -0.0280), ax, 0.0026, k("small"), slot_angle=45 if sx > 0 else 135))
    sp = L.fillet([(-0.1180, -0.0290, 0.006), (-0.0140, -0.0290, 0.006), (-0.0140, 0.0085, 0.006), (-0.1050, 0.0085, 0.012)], segs=6)
    sp.append(sp[0])
    g.spec["lines"].append({"kinds": [k("frame")], "normal": (1, 0, 0), "pts": sp, "width": 0.0003, "depth": 0.00025})
    # ---------------- barrel
    if carbine:
        br = [(-0.0050, 0.0105), (0.0, 0.0108), (0.0040, 0.0112), (0.0080, 0.0108), (BL * 0.5, 0.0098), (BL - 0.0012, 0.0090),
              (BL, 0.0085), (BL, 0.0068), (BL - 0.0010, 0.0057), (BL - 0.0012, 0.0055), (BL - 0.05, 0.0055)]
        g.add(L.loft("barrel", br, k("barrel"), 48))
        bar_top = lambda y: 0.0108 - (0.0108 - 0.0090) * y / BL
    else:
        br = [(-0.0050, 0.0118, "o"), (BL - 0.0012, 0.0101, "o"), (BL, 0.0096, "o"), (BL, 0.0070, "o"),
              (BL - 0.0010, 0.0058), (BL - 0.0012, 0.0056), (BL - 0.05, 0.0056)]
        g.add(L.loft("barrel", br, k("barrel"), 32))
        bar_top = lambda y: 0.0118 - (0.0118 - 0.0101) * y / BL
    # ---------------- magazine tube + bands
    TL = BL - (0.028 if carbine else 0.030)
    g.add(L.loft("tube", [(-0.002, 0.0080), (TL - 0.002, 0.0080), (TL, 0.0077)], k("tube"), 32, 0.0, TZ))
    g.add(L.loft("plug", [(TL, 0.0072), (TL + 0.0075, 0.0072), (TL + 0.0085, 0.0062), (TL + 0.009, 0.0040)], k("tube"), 32, 0.0, TZ))
    g.add(L.screw("plugscr", (0, TL + 0.004, TZ - 0.0072), "z-", 0.0018, k("small"), slot_angle=90))
    bands = [BL - 0.065] if not carbine else [0.215, BL - 0.045]
    for i, by in enumerate(bands):
        rb = bar_top(by)
        sec = _hull([(0, 0, rb + 0.0013), (0, TZ, 0.0080 + 0.0013)])
        g.add(L.extrude_xz("band%d" % i, sec, by, by + (0.010 if not carbine else 0.012), k("cap"), bev=0.0006, bseg=2))
        g.add(L.screw("bandscr%d" % i, (rb + 0.0016, by + 0.005, TZ * 0.45), "x+", 0.0016, k("small"), slot_angle=0))
    # ---------------- fore-end and cap
    FE = 0.215 if carbine else 0.255
    fe_out = L.catmull([(-0.004, 0.0035), (FE * 0.5, 0.0040), (FE + 0.006, 0.0035), (FE + 0.008, -0.010), (FE + 0.006, -0.0300),
                        (FE * 0.5, -0.0318), (-0.004, -0.0312), (-0.006, -0.012)], 6, closed=True)
    fore = _wood("fore", fe_out, lambda y, z: np.full_like(y, W - 0.0002), k("fore"), 0.009,
                 [[(0.0015, -0.06), (0.0015, 0.04), (-0.02, 0.04), (-0.02, -0.06)],
                  [(FE, -0.06), (FE + 0.03, -0.06), (FE + 0.03, 0.04), (FE, 0.04)]])
    g.add(fore)
    g.spec["grain"][k("fore")] = (0, 1, 0)
    if not carbine:
        rb = bar_top(FE)
        sec = _hull([(0, 0.001, rb + 0.0016), (0, TZ, 0.0080 + 0.0028), (0, -0.0105, W - 0.0004)], 24)
        g.add(L.extrude_xz("fecap", sec, FE, FE + 0.012, k("cap"), bev=0.0009, bseg=2))
    # ---------------- sights
    yr = 0.095 if carbine else 0.125
    zr = bar_top(yr)
    g.add(L.box("rsbase", -0.0045, 0.0045, yr - 0.016, yr + 0.010, zr - 0.0005, zr + 0.0022, k("sight"), bev=0.0004))
    leaf = [(-0.0105, zr + 0.0015), (0.0105, zr + 0.0015), (0.0105, zr + 0.0055, 0.002), (0.0080, zr + 0.0092, 0.0015),
            (0.0048, zr + 0.0072), (0.0013, zr + 0.0072), (0.0, zr + 0.0056), (-0.0013, zr + 0.0072), (-0.0048, zr + 0.0072),
            (-0.0080, zr + 0.0092, 0.0015), (-0.0105, zr + 0.0055, 0.002)]
    g.add(L.extrude_xz("rsleaf", leaf, yr, yr + 0.0014, k("sight"), bev=0.0002))
    g.add(L.box("rselev", -0.0035, 0.0035, yr - 0.014, yr - 0.002, zr + 0.0015, zr + 0.0042, k("sight"), bev=0.0003))
    g.spec["grooves"].append({"kinds": [k("sight")], "axis": (0, 1, 0), "range": (yr - 0.014, yr - 0.002), "pitch": 0.002,
                              "depth": 0.0003, "box": ((yr - 0.015, yr - 0.001), (zr + 0.003, zr + 0.006))})
    yf = BL - 0.014
    zf = bar_top(yf)
    g.add(L.box("fsbase", -0.0035, 0.0035, yf - 0.006, yf + 0.006, zf - 0.0005, zf + 0.0016, k("sight"), bev=0.0003))
    g.add(L.extrude("fsblade", [(yf - 0.0045, zf + 0.0012), (yf + 0.0045, zf + 0.0012), (yf + 0.0035, zf + 0.0062, 0.0015),
                                (yf - 0.0025, zf + 0.0062, 0.001)], -0.0007, 0.0007, k("sight"), bev=0.0002))
    # ---------------- tangs
    g.add(L.extrude("utang", [(RY0 + 0.004, 0.0082), (-0.212, -0.0046, 0.003), (-0.213, -0.0072), (RY0 + 0.004, 0.0056)],
                    -0.0062, 0.0062, k("frame"), bev=0.0006))
    g.add(L.screw("tangscr", (0, -0.200, -0.0030), "z+", 0.0022, k("small"), slot_angle=0))
    g.add(L.extrude("ltang", [(RY0 + 0.004, -0.0300), (-0.226, -0.0545), (-0.227, -0.0519), (RY0 + 0.006, -0.0272)],
                    -0.0068, 0.0068, k("frame"), bev=0.0006))
    # ---------------- butt stock
    heel = (-0.455, -0.050) if not carbine else (-0.440, -0.050)
    toe = (-0.462, -0.162) if not carbine else (-0.444, -0.160)
    st = L.catmull([(RY0 + 0.010, 0.0065), (-0.212, -0.0060), (-0.262, -0.0150), (heel[0] + 0.03, heel[1] + 0.004),
                    (heel[0] - 0.012, heel[1] + 0.001), (toe[0] - 0.012, toe[1] - 0.004), (toe[0] + 0.07, toe[1] + 0.030),
                    (-0.300, -0.0880), (-0.236, -0.0570), (-0.190, -0.0465), (RY0 + 0.010, -0.0285)], 6, closed=True)
    if carbine:
        bcurve = L.catmull([(heel[0], heel[1] + 0.006), (heel[0] - 0.006, -0.085), (heel[0] - 0.005, -0.125), (toe[0], toe[1] - 0.006)], 6)
    else:
        bcurve = L.catmull([(heel[0] - 0.003, heel[1] + 0.006), (heel[0] + 0.005, -0.078), (heel[0] + 0.006, -0.108),
                            (heel[0] + 0.001, -0.138), (toe[0], toe[1] - 0.006)], 6)
    behind = bcurve + [(toe[0] - 0.05, toe[1] - 0.02), (heel[0] - 0.05, heel[1] + 0.03)]

    def shw(y, z):
        t = np.clip((-y - 0.180) / 0.25, 0, 1)
        return 0.0132 + 0.0072 * t * t * (3 - 2 * t)
    stock = _wood("stock", st, shw, k("wood"), 0.0105, [behind, [(RY0 + 0.002, -0.08), (RY0 + 0.03, -0.08), (RY0 + 0.03, 0.03),
                                                             (RY0 + 0.002, 0.03)]], step=0.005)
    g.add(stock)
    g.spec["grain"][k("wood")] = (0, 1, -0.12)
    g.spec["grain_center"][k("wood")] = (0.05, -0.2, 0.3)
    # wrist checkering, both sides
    g.spec["checker"].append({"kinds": [k("wood")], "normal": (1, 0, 0), "min_dot": 0.55, "center": (-0.200, -0.027),
                              "radii": (0.028, 0.016), "angle": -18.0, "pitch": 0.0018, "depth": 0.0003, "border": True})
    # butt plate following the butt curve
    off = [(p[0] - 0.0018, p[1]) for p in bcurve]
    bw = 2 * shw(np.array([heel[0]]), None)[0] - 0.003
    bp = L.sweep("buttplate", L.path_yz(off), L.section_rect(bw, 0.0040, 0.0035), k("butt"))
    g.add(bp)
    if not carbine:
        # crescent horn at the toe and heel tang
        g.add(L.extrude("heeltang", [(heel[0] - 0.002, heel[1] + 0.0065), (heel[0] + 0.030, heel[1] + 0.0098, 0.003),
                                     (heel[0] + 0.030, heel[1] + 0.0074), (heel[0] - 0.002, heel[1] + 0.0035)],
                        -0.006, 0.006, k("butt"), bev=0.0005))
    for (py, pz) in ((heel[0] + 0.004, -0.050), (heel[0] + 0.004, -0.120)):
        g.add(L.screw("bpscr", (0, py - 0.0045, pz), "y-", 0.0022, k("small"), slot_angle=0))
    # ---------------- loading gate (part): spring flap on the right side, hinged at its front edge
    gate_prof = [(-0.0200, -0.0105), (-0.0560, -0.0105, 0.004), (-0.0560, -0.0262, 0.004), (-0.0200, -0.0262)]
    g.part("loading_gate", (W, -0.0200, -0.018), {"type": "rot", "axis": (0, 0, 1), "open": -22.0})
    g.add(L.extrude("gate", gate_prof, W - 0.0004, W + 0.0007, k("frame"), bev=0.0003), "loading_gate")
    # ---------------- bolt (part): slides back when the lever opens, protruding over the tang
    g.part("bolt", (0, -0.085, 0.0), {"type": "slide", "axis": (0, -1, 0), "open": 0.052})
    bsec = [(-0.0055, -0.0060), (0.0055, -0.0060), (0.0055, 0.0094, 0.0015), (-0.0055, 0.0094, 0.0015)]
    g.add(L.extrude_xz("boltb", bsec, -0.1290, -0.0420, k("bolt"), bev=0.0004), "bolt")
    g.add(L.box("extractor", -0.0016, 0.0016, -0.075, -0.040, 0.0090, 0.0110, k("bolt"), bev=0.0003), "bolt")
    g.add(L.loft("fpin", [(-0.1320, 0.0018), (-0.1288, 0.0018)], k("bolt"), 12, 0, 0.003), "bolt")
    g.spec["grooves"].append({"kinds": [k("bolt")], "axis": (0, 1, 0), "range": (-0.128, -0.110), "pitch": 0.0011,
                              "depth": 0.0002, "box": ((-0.13, -0.10), (0.008, 0.012))})
    # ---------------- hammer (part)
    hpv = (-0.1470, -0.0200)
    hprof = [(-0.1300, -0.0080, 0.002), (-0.1300, 0.0080, 0.0015), (-0.1345, 0.0130, 0.003), (-0.1420, 0.0160, 0.005),
             (-0.1540, 0.0215, 0.006), (-0.1665, 0.0270, 0.003), (-0.1700, 0.0248, 0.002), (-0.1650, 0.0185, 0.004),
             (-0.1565, 0.0105, 0.006), (-0.1525, 0.0000, 0.004), (-0.1560, -0.0200, 0.005), (-0.1480, -0.0285, 0.004),
             (-0.1380, -0.0200, 0.003)]
    g.part("hammer", (0, hpv[0], hpv[1]), {"type": "rot", "axis": (1, 0, 0), "open": 52.0, "half": 18.0})
    g.add(L.extrude("hammer_b", hprof, -0.0042, 0.0042, k("hammer"), bev=0.0005), "hammer")
    g.spec["checker"].append({"kinds": [k("hammer")], "normal": (0, -0.4, 0.9), "min_dot": 0.45, "center": (-0.1640, 0.0255),
                              "radii": (0.005, 0.006), "angle": 25.0, "pitch": 0.0010, "depth": 0.00025, "border": False,
                              "shape": "box"})
    # ---------------- trigger (part)
    tpv = (-0.0935, -0.0320)
    g.part("trigger", (0, tpv[0], tpv[1]), {"type": "rot", "axis": (1, 0, 0), "open": -12.0})
    tprof = [(-0.0915, -0.0300), (-0.0905, -0.0400, 0.002), (-0.0925, -0.0470, 0.004), (-0.0962, -0.0525, 0.002),
             (-0.0985, -0.0516, 0.0012), (-0.0975, -0.0462, 0.004), (-0.0957, -0.0400, 0.002), (-0.0965, -0.0300)]
    g.add(L.extrude("trigger_b", tprof, -0.0020, 0.0020, k("small"), bev=0.0004), "trigger")
    # ---------------- lever (part): body under the receiver, finger loop, tail along the wrist
    lpv = (-0.0180, -0.0280)
    g.part("lever", (0, lpv[0], lpv[1]), {"type": "rot", "axis": (1, 0, 0), "open": 50.0})
    lbody = [(-0.0090, -0.0280, 0.006), (-0.0140, -0.0405, 0.004), (-0.0640, -0.0412, 0.003), (-0.1230, -0.0412, 0.004),
             (-0.2020, -0.0532, 0.003), (-0.2050, -0.0500, 0.0015), (-0.1260, -0.0345, 0.003), (-0.0300, -0.0336, 0.004),
             (-0.0200, -0.0215, 0.005)]
    g.add(L.extrude("lever_b", lbody, -0.0050, 0.0050, k("lever"), bev=0.0006), "lever")
    loop = L.catmull([(-0.0590, -0.0395), (-0.0610, -0.0580), (-0.0720, -0.0780), (-0.0920, -0.0880), (-0.1130, -0.0850),
                      (-0.1255, -0.0715), (-0.1290, -0.0545), (-0.1250, -0.0410)], 6)
    g.add(L.sweep("loop", L.path_yz(loop), L.section_rect(0.0090, 0.0062, 0.0025), k("lever")), "lever")
    if carbine:
        # saddle ring on the left side of the receiver
        g.add(L.loft("ringstud", [(0, 0.0032), (0.004, 0.0032), (0.0045, 0.0020)], k("small"), 16))
        stud = g.static[-1]
        L.transform(stud, L.rot_z(90))
        L.move(stud, (-W, -0.110, -0.010))
        ring = [(math.cos(a) * 0.0115, math.sin(a) * 0.0115 - 0.0115) for a in np.linspace(0, math.tau, 33)[:-1]]
        rg = L.sweep("ring", [(-W - 0.0055, -0.110 + p[0], -0.010 + p[1]) for p in ring], L.section_ellipse(0.0024, 0.0024, 10),
                     k("ring"), closed_path=True)
        g.add(rg)
    # ---------------- markers
    g.marker("muzzle", (0, BL, 0))
    g.marker("grip_r", (0, -0.188, -0.030))
    g.marker("grip_l", (0, 0.120 if carbine else 0.140, -0.020))
    g.marker("sight_rear", (0, yr, zr + 0.0056))
    g.marker("sight_front", (0, yf, zf + 0.0062))
    g.marker("holster_attach", (0, -0.02, -0.010))
    g.marker("shell_eject", (0, -0.082, TOP + 0.002), fwd=(0.35, -0.25, 1.0), up=(0, 1, 0))
    g.spec["handling"] += [((-0.13, -0.03), (-0.035, 0.016), 0.5), ((0.05, FE), (-0.035, 0.0), 0.3)]
    g.detail_target = (0.0, -0.085, -0.012)


def build_merriman(g):
    build_lever(g, carbine=False)


def build_harlan(g):
    build_lever(g, carbine=True)


BUILDERS = {"merriman_lever": build_merriman, "harlan_carbine": build_harlan}
