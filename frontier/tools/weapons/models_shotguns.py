"""Shotguns: Calder Double-Barrel (side-by-side hammer gun: back-action locks, top lever, twin triggers, splinter
fore-end, barrels tip down on the hinge pin) and Brennan Slide-Action (exposed-hammer pump gun with a grooved slide
handle, side ejection port, tube magazine). Original designs."""
import math

import numpy as np

import gun_lib as L
from gun_rig import FINISHES, Gun
from models_levers import _hull, _wood
from models_rifles import _butt_plate, _guard, _stock_cut, _trigger

FINISHES["calder_double"] = {"standard": {"frame": "case", "barrel": "blued", "hammer": "case", "small": "blued", "lever": "case",
                                          "wood": "walnut", "fore": "walnut_fore", "butt": "blued", "cart": "cart", "hull": "brass"}}
FINISHES["brennan_pump"] = {"standard": {"frame": "blued", "barrel": "blued", "hammer": "case", "small": "blued", "bolt": "steel",
                                         "wood": "walnut", "fore": "walnut_fore", "butt": "rubber", "tube": "blued"}}


# ============================================================================================ Calder double
def build_calder(g: Gun):
    k = g.k
    BL = 0.710
    X = 0.0118                      # bore axes at x = +-X
    RB = 0.0093                     # 12 bore
    HY, HZ = 0.056, -0.0230         # hinge pin
    # ---------------- action body (static)
    prof = [(0.0, 0.0140, 0.002), (0.0, -0.0140), (HY - 0.004, -0.0140), (HY + 0.004, -0.0200, 0.004), (HY + 0.002, -0.0330, 0.004),
            (0.010, -0.0360, 0.006), (-0.040, -0.0380, 0.006), (-0.070, -0.0320, 0.006), (-0.078, 0.0060, 0.006), (-0.040, 0.0150, 0.010)]
    body = L.extrude("action", prof, -0.0215, 0.0215, k("frame"), bev=0.0008)
    L.boolean(body, [L.box("barcut", -0.03, 0.03, 0.0005, HY - 0.004, -0.0136, 0.03, "blued", bev=0)])
    L.bevel(body, 0.0004, 1, 40)
    L.finish(body)
    g.add(body)
    # fences: rounded shoulders behind each barrel
    for sx in (-X, X):
        f = L.sphere("fence", 0.0140, (sx, -0.004, 0.0), k("frame"), 28)
        L.boolean(f, [L.box("fcut", -0.05, 0.05, 0.0, 0.05, -0.05, 0.05, "blued", bev=0)])
        L.finish(f, math.radians(70))
        g.add(f)
        g.add(L.loft("striker", [(-0.0130, 0.0012), (-0.0060, 0.0012)], k("small"), 12, sx, 0.0040), uvs=0.4)
    # lock plates (both sides) and screws
    lp = [(0.040, -0.0050, 0.004), (0.040, -0.0250, 0.006), (-0.020, -0.0280, 0.006), (-0.072, -0.0200, 0.010), (-0.074, 0.0000, 0.008),
          (-0.040, 0.0060, 0.008), (0.010, 0.0050, 0.006)]
    for s in (-1, 1):
        x0, x1 = (0.0212, 0.0236) if s > 0 else (-0.0236, -0.0212)
        g.add(L.extrude("lock", lp, x0, x1, k("frame"), bev=0.0005))
        g.add(L.screw("lockscr", (s * 0.0237, -0.030, -0.010), "x+" if s > 0 else "x-", 0.0024, k("small"), slot_angle=40))
        g.add(L.screw("tumbler", (s * 0.0237, -0.035, 0.000), "x+" if s > 0 else "x-", 0.0030, k("small"), slot_angle=100))
        g.spec["lines"].append({"kinds": [k("frame")], "normal": (1, 0, 0), "pts": [(0.005, 0.0045), (0.030, -0.0060), (0.030, -0.0230)],
                                "width": 0.0003, "depth": 0.0002})
    g.add(L.screw("hingepin", (0.0216, HY, HZ), "x+", 0.0045, k("small"), slot_angle=0))
    g.add(L.screw("hingepin2", (-0.0216, HY, HZ), "x-", 0.0045, k("small"), slot_angle=0))
    # tangs, guard, stock
    g.add(L.extrude("utang", [(-0.070, 0.0120), (-0.140, -0.0020, 0.003), (-0.141, -0.0046), (-0.070, 0.0094)], -0.0065, 0.0065,
                    k("frame"), bev=0.0006))
    g.add(L.extrude("ltang", [(-0.050, -0.0360), (-0.180, -0.0560, 0.003), (-0.181, -0.0534), (-0.050, -0.0334)], -0.0068, 0.0068,
                    k("frame"), bev=0.0006))
    _guard(g, [(-0.030, -0.0370), (-0.031, -0.0490), (-0.043, -0.0640), (-0.070, -0.0660), (-0.088, -0.0540), (-0.091, -0.0400)], k("frame"),
           w=0.0095)
    _trigger(g, (-0.046, -0.0360), 0.022, k("small"), "trigger")
    _trigger(g, (-0.066, -0.0360), 0.020, k("small"), "trigger_2")
    heel, toe = (-0.420, -0.045), (-0.424, -0.160)
    bcurve = L.catmull([(heel[0], heel[1] + 0.005), (heel[0] - 0.004, -0.090), (heel[0] - 0.003, -0.128), (toe[0], toe[1] - 0.005)], 6)
    st = L.catmull([(-0.072, 0.0130), (-0.140, -0.0010), (-0.200, -0.0130), (heel[0] + 0.02, heel[1] + 0.003), (heel[0] - 0.012, heel[1]),
                    (toe[0] - 0.012, toe[1] - 0.004), (toe[0] + 0.07, toe[1] + 0.030), (-0.240, -0.0760), (-0.190, -0.0570),
                    (-0.130, -0.0470), (-0.072, -0.0360)], 6, closed=True)

    def hw(y, z):
        t = np.clip((-y - 0.16) / 0.22, 0, 1)
        return 0.0150 + 0.0060 * t * t * (3 - 2 * t) + 0.006 * np.clip((y + 0.11) / 0.04, 0, 1)
    behind, _ = _stock_cut(heel, toe, bcurve, 0.0)
    g.add(_wood("stock", st, hw, k("wood"), 0.0105, [behind, [(-0.076, -0.08), (-0.02, -0.08), (-0.02, 0.03), (-0.076, 0.03)]], step=0.0045))
    g.spec["grain"][k("wood")] = (0, 1, -0.12)
    g.spec["checker"].append({"kinds": [k("wood")], "normal": (1, 0, 0), "min_dot": 0.55, "center": (-0.135, -0.024), "radii": (0.030, 0.015),
                              "angle": -12.0, "pitch": 0.0016, "depth": 0.0003, "border": True})
    _butt_plate(g, bcurve, 2 * hw(np.array([heel[0]]), None)[0] - 0.003, k("butt"))
    # hammers on the locks (parts)
    hp = [(-0.0060, -0.0060, 0.003), (-0.0020, 0.0060, 0.003), (0.0010, 0.0120, 0.002), (-0.0030, 0.0175, 0.003), (-0.0090, 0.0150, 0.003),
          (-0.0120, 0.0120, 0.004), (-0.0200, 0.0160, 0.004), (-0.0300, 0.0230, 0.003), (-0.0330, 0.0215, 0.002), (-0.0250, 0.0110, 0.005),
          (-0.0190, 0.0020, 0.006), (-0.0200, -0.0080, 0.006), (-0.0130, -0.0110, 0.005)]
    for name, s in (("hammer_r", 1), ("hammer_l", -1)):
        g.part(name, (s * 0.0250, -0.0350, -0.0020), {"type": "rot", "axis": (1, 0, 0), "open": 48.0, "half": 18.0})
        hm = L.extrude(name + "_b", [(y - 0.012, z) + tuple(r) for (y, z, *r) in hp], s * 0.0236, s * 0.0290, k("hammer"), bev=0.0005)
        # neck bends inward so the nose strikes the fence-mounted striker
        L.deform(hm, lambda co, s=s: co + np.stack([-s * np.clip((co[:, 2] - 0.002) / 0.014, 0, 1) * 0.0085, co[:, 1] * 0, co[:, 2] * 0], 1))
        g.add(hm, name)
        g.spec["checker"].append({"kinds": [k("hammer")], "normal": (0, -0.4, 0.9), "min_dot": 0.4, "center": (-0.0410, 0.0225),
                                  "radii": (0.0045, 0.006), "angle": 25.0, "pitch": 0.0010, "depth": 0.00025, "border": False, "shape": "box"})
    # top lever (part): swings right about a vertical pin
    g.part("top_lever", (0, -0.0300, 0.0140), {"type": "rot", "axis": (0, 0, 1), "open": 50.0})
    g.add(L.extrude_xy("toplever", [(-0.0045, -0.0240, 0.003), (0.0045, -0.0240, 0.003), (0.0060, -0.0560, 0.004), (0.0020, -0.0700, 0.003),
                                    (-0.0040, -0.0690, 0.003), (-0.0055, -0.0560, 0.004)], 0.0115, 0.0150, k("lever"), bev=0.0005), "top_lever")
    g.spec["checker"].append({"kinds": [k("lever")], "normal": (0, 0, 1), "min_dot": 0.6, "center": (-0.062, 0.0), "radii": (0.007, 0.005),
                              "angle": 90.0, "pitch": 0.0010, "depth": 0.0002, "border": False, "shape": "box"})
    # ---------------- barrels (part) with ribs, lumps, fore-end, extractor and loaded shells
    g.part("barrels", (0, HY, HZ), {"type": "rot", "axis": (1, 0, 0), "open": -38.0})
    for sx in (-X, X):
        br = [(0.0, 0.0124), (0.080, 0.0120), (0.090, 0.0116), (BL - 0.0012, 0.0104), (BL, 0.0100), (BL, RB + 0.0004), (BL - 0.002, RB),
              (0.0005, RB), (0.0005, 0.0108), (0.0, 0.0110), (0.0, 0.0124)]
        g.add(L.loft("barrel", br, k("barrel"), 48, sx, 0.0, cap0=False, cap1=False), "barrels")
    g.add(L.extrude_xz("toprib", [(-0.0065, 0.0060), (0.0065, 0.0060), (0.0062, 0.0126, 0.001), (0.0, 0.0118), (-0.0062, 0.0126, 0.001)],
                       0.0, BL - 0.002, k("barrel"), bev=0.0002), "barrels")
    g.add(L.extrude_xz("botrib", [(-0.0060, -0.0060), (0.0060, -0.0060), (0.0060, -0.0110), (-0.0060, -0.0110)], 0.090, BL - 0.004,
                       k("barrel"), bev=0.0002), "barrels")
    g.add(L.sphere("bead", 0.0016, (0, BL - 0.010, 0.0128), k("small"), 12), "barrels")
    g.add(L.extrude("lumps", [(0.0005, -0.0080), (0.060, -0.0080), (0.064, -0.0150, 0.003), (0.060, -0.0300, 0.006), (0.040, -0.0300, 0.004),
                              (0.0005, -0.0140)], -0.0090, 0.0090, k("barrel"), bev=0.0005), "barrels")
    fe = L.catmull([(0.066, -0.0090), (0.180, -0.0095), (0.282, -0.0100), (0.292, -0.0160), (0.282, -0.0270), (0.180, -0.0275),
                    (0.070, -0.0300), (0.064, -0.0200)], 6, closed=True)
    g.add(_wood("fore", fe, lambda y, z: np.full_like(y, 0.0175), k("fore"), 0.009, []), "barrels")
    g.spec["grain"][k("fore")] = (0, 1, 0)
    g.add(L.extrude("feiron", [(0.064, -0.0220), (0.100, -0.0280, 0.003), (0.100, -0.0300), (0.064, -0.0300, 0.003)], -0.0110, 0.0110,
                    k("frame"), bev=0.0004), "barrels")
    g.part("extractor", (0, 0.010, 0.0), {"type": "slide", "axis": (0, -1, 0), "open": 0.006}, parent="barrels")
    g.add(L.extrude("extr", [(0.0005, -0.0040), (0.030, -0.0040), (0.030, 0.0040), (0.0005, 0.0040)], -0.0050, 0.0050, k("small"), bev=0.0003),
          "extractor")
    for sx in (-X, X):
        g.add(L.loft("rim", [(0.0001, 0.0098), (0.0010, 0.0108), (0.0016, 0.0108), (0.0016, RB - 0.0002), (0.010, RB - 0.0002)],
                     k("cart"), 32, sx, 0.0), "extractor", uvs=0.4)
        g.add(L.loft("primer", [(-0.0002, 0.0025), (0.0006, 0.0025)], k("cart"), 16, sx, 0.0), "extractor", uvs=0.3)
    g.marker("muzzle", (0, BL, 0))
    g.marker("grip_r", (0, -0.150, -0.032))
    g.marker("grip_l", (0, 0.170, -0.022))
    g.marker("sight_rear", (0, 0.0, 0.0135))
    g.marker("sight_front", (0, BL - 0.010, 0.0144))
    g.marker("holster_attach", (0, 0.020, -0.010))
    g.marker("shell_eject", (0, 0.002, 0.0), fwd=(0.0, -1.0, 0.9))
    g.spec["handling"] += [((-0.17, -0.09), (-0.06, 0.02), 0.4), ((0.07, 0.29), (-0.03, -0.005), 0.4)]
    g.detail_target = (0.0, -0.020, 0.0)


# ============================================================================================ Brennan pump
def build_brennan(g: Gun):
    k = g.k
    BL = 0.710
    RB = 0.0093
    TZ = -0.0250
    W = 0.0130
    prof = [(0.0, -0.0360, 0.004), (0.0, 0.0130, 0.004), (-0.0060, 0.0160, 0.004), (-0.1800, 0.0160, 0.010), (-0.2050, 0.0060, 0.006),
            (-0.2080, -0.0250, 0.005), (-0.1950, -0.0360, 0.006)]
    rec = L.extrude("receiver", prof, -W, W, k("frame"), bev=0.0008)
    L.boolean(rec, [L.box("port", 0.006, 0.03, -0.122, -0.044, -0.0110, 0.0115, "blued", bev=0),
                    L.box("hslot", -0.0050, 0.0050, -0.215, -0.172, -0.026, 0.03, "blued", bev=0),
                    L.box("bway", -0.0098, 0.0098, -0.150, -0.040, -0.0135, 0.0115, "blued", bev=0)])
    L.bevel(rec, 0.0004, 1, 40)
    L.finish(rec)
    g.add(rec)
    for sx, ax in ((W + 0.0001, "x+"), (-W - 0.0001, "x-")):
        g.add(L.screw("rs1", (sx, -0.165, -0.020), ax, 0.0025, k("small"), slot_angle=30 if sx > 0 else 120))
        g.add(L.screw("rs2", (sx, -0.020, -0.026), ax, 0.0022, k("small"), slot_angle=80 if sx > 0 else 10))
    g.spec["lines"].append({"kinds": [k("frame")], "normal": (1, 0, 0), "pts": [(-0.160, -0.0290), (-0.030, -0.0290)], "width": 0.0003,
                            "depth": 0.0002})
    br = [(-0.006, 0.0138), (0.050, 0.0138), (0.056, 0.0122), (BL - 0.0012, 0.0106), (BL, 0.0102), (BL, RB + 0.0004), (BL - 0.002, RB),
          (BL - 0.10, RB)]
    g.add(L.loft("barrel", br, k("barrel"), 48))
    g.add(L.sphere("bead", 0.0016, (0, BL - 0.010, 0.0116), k("small"), 12))
    g.add(L.loft("tube", [(-0.002, 0.0100), (0.556, 0.0100), (0.558, 0.0096)], k("tube"), 32, 0.0, TZ))
    g.add(L.loft("tcap", [(0.558, 0.0092), (0.574, 0.0092), (0.578, 0.0080), (0.580, 0.0050)], k("tube"), 32, 0.0, TZ))
    g.spec["grooves"].append({"kinds": [k("tube")], "axis": (0, 1, 0), "range": (0.560, 0.573), "pitch": 0.0012, "depth": 0.0002,
                              "box": ((0.556, 0.576), (TZ - 0.012, TZ + 0.012))})
    g.add(L.extrude_xz("band", _hull([(0, 0.0, 0.0118), (0, TZ, 0.0112)]), 0.530, 0.540, k("frame"), bev=0.0005))
    _guard(g, [(-0.120, -0.0370), (-0.121, -0.0490), (-0.132, -0.0620), (-0.156, -0.0640), (-0.172, -0.0520), (-0.175, -0.0380)], k("frame"))
    _trigger(g, (-0.138, -0.0360), 0.022, k("small"))
    g.add(L.extrude("ltang", [(-0.190, -0.0360), (-0.270, -0.0560, 0.003), (-0.271, -0.0534), (-0.190, -0.0334)], -0.0068, 0.0068,
                    k("frame"), bev=0.0006))
    g.add(L.extrude("utang", [(-0.200, 0.0080), (-0.258, -0.0020, 0.003), (-0.259, -0.0046), (-0.200, 0.0054)], -0.0062, 0.0062,
                    k("frame"), bev=0.0006))
    # hammer (part)
    g.part("hammer", (0, -0.1930, -0.0160), {"type": "rot", "axis": (1, 0, 0), "open": 50.0, "half": 18.0})
    hp = [(-0.1780, -0.0080, 0.002), (-0.1780, 0.0080, 0.0015), (-0.1830, 0.0140, 0.003), (-0.1920, 0.0175, 0.005), (-0.2040, 0.0230, 0.005),
          (-0.2150, 0.0280, 0.003), (-0.2180, 0.0258, 0.002), (-0.2120, 0.0190, 0.004), (-0.2030, 0.0110, 0.006), (-0.1990, 0.0000, 0.004),
          (-0.2020, -0.0200, 0.005), (-0.1940, -0.0280, 0.004), (-0.1840, -0.0200, 0.003)]
    g.add(L.extrude("hammer_b", hp, -0.0045, 0.0045, k("hammer"), bev=0.0005), "hammer")
    g.spec["checker"].append({"kinds": [k("hammer")], "normal": (0, -0.4, 0.9), "min_dot": 0.45, "center": (-0.2130, 0.0262),
                              "radii": (0.005, 0.006), "angle": 25.0, "pitch": 0.0010, "depth": 0.00025, "border": False, "shape": "box"})
    # bolt (part) seen through the port; moves with the slide
    g.part("bolt", (0, -0.090, 0.0), {"type": "slide", "axis": (0, -1, 0), "open": 0.080})
    g.add(L.box("boltb", -0.0094, 0.0094, -0.140, -0.042, -0.0130, 0.0110, k("bolt"), bev=0.0006), "bolt")
    g.add(L.box("bextr", 0.0090, 0.0104, -0.060, -0.042, -0.0030, 0.0040, k("bolt"), bev=0.0003), "bolt")
    g.spec["grooves"].append({"kinds": [k("bolt")], "axis": (0, 1, 0), "range": (-0.14, -0.06), "pitch": 0.003, "depth": 0.0004,
                              "box": ((-0.14, -0.06), (-0.012, 0.010))})
    # slide handle (part): turned walnut with ring grooves + action bars
    g.part("pump", (0, 0.190, TZ), {"type": "slide", "axis": (0, -1, 0), "open": 0.080})
    st = [(0.090, 0.0104), (0.092, 0.0150), (0.096, 0.0172)]
    y = 0.104
    while y < 0.270:
        st += [(y - 0.0012, 0.0176), (y, 0.0164), (y + 0.0012, 0.0176)]
        y += 0.010
    st += [(0.282, 0.0172), (0.288, 0.0150), (0.290, 0.0104)]
    g.add(L.loft("slide", st, k("fore"), 40, 0.0, TZ, scale_x=0.95), "pump")
    g.spec["grain"][k("fore")] = (0, 1, 0)
    for s in (-1, 1):
        g.add(L.box("abar", s * 0.0098 - 0.0010, s * 0.0098 + 0.0010, -0.020, 0.096, TZ - 0.0040, TZ + 0.0040, k("small"), bev=0.0003), "pump")
    # stock
    heel, toe = (-0.540, -0.050), (-0.545, -0.165)
    bcurve = L.catmull([(heel[0], heel[1] + 0.005), (heel[0] - 0.004, -0.095), (heel[0] - 0.003, -0.132), (toe[0], toe[1] - 0.005)], 6)
    stk = L.catmull([(-0.202, 0.0080), (-0.258, -0.0050), (-0.310, -0.0150), (heel[0] + 0.02, heel[1] + 0.003), (heel[0] - 0.012, heel[1]),
                     (toe[0] - 0.012, toe[1] - 0.004), (toe[0] + 0.07, toe[1] + 0.030), (-0.360, -0.0800), (-0.300, -0.0620),
                     (-0.250, -0.0530), (-0.202, -0.0340)], 6, closed=True)

    def hw(y, z):
        t = np.clip((-y - 0.28) / 0.22, 0, 1)
        return 0.0136 + 0.0074 * t * t * (3 - 2 * t)
    behind, _ = _stock_cut(heel, toe, bcurve, 0.0)
    g.add(_wood("stock", stk, hw, k("wood"), 0.0105, [behind, [(-0.205, -0.08), (-0.15, -0.08), (-0.15, 0.03), (-0.205, 0.03)]], step=0.0045))
    g.spec["grain"][k("wood")] = (0, 1, -0.12)
    _butt_plate(g, bcurve, 2 * hw(np.array([heel[0]]), None)[0] - 0.003, k("butt"))
    g.spec["grooves"].append({"kinds": [k("butt")], "axis": (0, 0.1, 1), "range": (-0.3, 0.3), "pitch": 0.0030, "depth": 0.0004})
    g.marker("muzzle", (0, BL, 0))
    g.marker("grip_r", (0, -0.265, -0.032))
    g.marker("grip_l", (0, 0.190, TZ))
    g.marker("sight_rear", (0, -0.100, 0.0165))
    g.marker("sight_front", (0, BL - 0.010, 0.0132))
    g.marker("holster_attach", (0, 0.0, -0.010))
    g.marker("shell_eject", (0.015, -0.085, 0.0), fwd=(1.0, -0.15, 0.5))
    g.spec["handling"] += [((-0.29, -0.20), (-0.06, 0.02), 0.4)]
    g.detail_target = (0.0, -0.100, -0.005)


BUILDERS = {"calder_double": build_calder, "brennan_pump": build_brennan}
