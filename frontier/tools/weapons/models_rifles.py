"""Rifles: Bowden Bolt Rifle (turn-bolt military-pattern rifle, full stock, handguard, bands, box magazine),
Pellman .22 Varmint (slim small-bore bolt rifle with tube magazine), Vance Rolling Block (heavy single-shot with
rotating breechblock and hammer, octagon barrel, tang peep sight). Original designs."""
import math

import numpy as np

import gun_lib as L
from gun_rig import FINISHES, Gun
from models_levers import _hull, _wood

FINISHES["bowden_bolt"] = {"standard": {"frame": "blued", "barrel": "blued", "bolt": "steel", "small": "blued", "band": "blued",
                                        "wood": "walnut", "fore": "walnut", "sight": "blued", "butt": "blued", "swivel": "iron"}}
FINISHES["pellman_varmint"] = {"standard": {"frame": "blued", "barrel": "blued", "bolt": "steel", "small": "blued",
                                            "wood": "oak", "sight": "blued", "butt": "rubber", "tube": "blued"}}
FINISHES["vance_rolling"] = {"standard": {"frame": "case", "barrel": "blued", "hammer": "case", "breech": "case", "small": "blued",
                                          "wood": "walnut", "fore": "walnut_fore", "sight": "blued", "butt": "case"}}


def _stock_cut(heel, toe, bcurve, front_y):
    behind = bcurve + [(toe[0] - 0.05, toe[1] - 0.02), (heel[0] - 0.05, heel[1] + 0.03)]
    front = [(front_y, -0.10), (front_y + 0.06, -0.10), (front_y + 0.06, 0.04), (front_y, 0.04)]
    return behind, front


def _butt_plate(g, bcurve, width, kind, screws=True):
    off = [(p[0] - 0.0018, p[1]) for p in bcurve]
    g.add(L.sweep("buttplate", L.path_yz(off), L.section_rect(width, 0.0042, 0.0035), kind))
    if screws:
        n = len(bcurve)
        for i in (n // 5, (4 * n) // 5):
            py, pz = bcurve[i]
            g.add(L.screw("bpscr", (0, py - 0.0040, pz), "y-", 0.0022, g.k("small"), slot_angle=0))


def _guard(g, path, kind, w=0.0085, h=0.0036):
    g.add(L.sweep("guard", L.path_yz(L.catmull(path, 5)), L.section_rect(w, h, 0.0015), kind))


def _trigger(g, pivot, drop, kind, part="trigger", width=0.0021, open_deg=-12.0):
    py, pz = pivot
    g.part(part, (0, py, pz), {"type": "rot", "axis": (1, 0, 0), "open": open_deg})
    prof = [(py + 0.0020, pz + 0.002), (py + 0.0028, pz - drop * 0.35, 0.002), (py + 0.0008, pz - drop * 0.7, 0.004),
            (py - 0.0030, pz - drop, 0.0015), (py - 0.0050, pz - drop + 0.0012, 0.0012), (py - 0.0030, pz - drop * 0.68, 0.004),
            (py - 0.0012, pz - drop * 0.35, 0.002), (py - 0.0020, pz + 0.002)]
    g.add(L.extrude(part + "_b", prof, -width, width, kind, bev=0.0004), part)


def _swivel(g, y, z, kind, axis_z=True):
    ring = [(math.cos(a) * 0.0085, math.sin(a) * 0.0060) for a in np.linspace(0, math.tau, 25)[:-1]]
    g.add(L.sweep("swivel", [(0, y + p[0], z - 0.0065 + p[1]) for p in ring], L.section_ellipse(0.0022, 0.0022, 8), kind,
                  closed_path=True), uvs=0.5)


# ============================================================================================ Bowden bolt rifle
def build_bowden(g: Gun):
    k = g.k
    BL = 0.740
    # barrel with a stepped shank and taper
    br = [(-0.010, 0.0142), (0.030, 0.0142), (0.034, 0.0128), (0.300, 0.0118), (0.306, 0.0112), (BL - 0.0012, 0.0094),
          (BL, 0.0090), (BL, 0.0062), (BL - 0.0010, 0.0053), (BL - 0.0012, 0.0052), (BL - 0.08, 0.0052)]
    g.add(L.loft("barrel", br, k("barrel"), 48))
    # receiver: round, with an open top/right loading port, recoil lug and rear tang
    rec = L.loft("receiver", [(-0.178, 0.0140), (-0.176, 0.0160), (-0.002, 0.0160), (0.0, 0.0150)], k("frame"), 48)
    port = L.box("port", -0.0080, 0.03, -0.118, -0.034, 0.0015, 0.03, "blued", bev=0)
    bore = L.loft("bway", [(-0.19, 0.0094), (-0.03, 0.0094)], "blued", 32)
    L.boolean(rec, [port, bore])
    L.bevel(rec, 0.0004, 1, 40)
    L.finish(rec)
    g.add(rec)
    g.add(L.box("lug", -0.010, 0.010, -0.022, -0.008, -0.024, -0.010, k("frame"), bev=0.0005))
    g.add(L.extrude("tang", [(-0.176, 0.0050), (-0.236, -0.0025, 0.003), (-0.237, -0.0050), (-0.176, 0.0015)], -0.0060, 0.0060,
                    k("frame"), bev=0.0006))
    g.add(L.screw("tscr", (0, -0.224, -0.0026), "z+", 0.0021, k("small")))
    g.add(L.box("floor", -0.0112, 0.0112, -0.120, -0.040, -0.0520, -0.0455, k("small"), bev=0.0007))
    g.add(L.screw("fscr", (0, -0.046, -0.0522), "z-", 0.0021, k("small"), slot_angle=90))
    _guard(g, [(-0.1200, -0.0480), (-0.1225, -0.0600), (-0.1350, -0.0720), (-0.1580, -0.0725), (-0.1720, -0.0610), (-0.1750, -0.0500)],
           k("small"))
    g.add(L.extrude("gtang", [(-0.172, -0.0478), (-0.215, -0.0590, 0.002), (-0.216, -0.0565), (-0.172, -0.0455)], -0.0060, 0.0060,
                    k("small"), bev=0.0005))
    _trigger(g, (-0.130, -0.0440), 0.024, k("small"))
    # bolt (part): lift the handle (rotate about the bore) then draw back
    g.part("bolt", (0, -0.100, 0), {"type": "bolt", "axis": (0, -1, 0), "open": 0.090, "rot_axis": (0, 1, 0), "rot": -78.0})
    g.add(L.loft("boltbody", [(-0.183, 0.0086), (-0.040, 0.0088), (-0.038, 0.0080)], k("bolt"), 32), "bolt")
    g.add(L.box("blug1", -0.0030, 0.0030, -0.050, -0.040, 0.0080, 0.0104, k("bolt"), bev=0.0003), "bolt")
    g.add(L.box("extr", 0.0080, 0.0098, -0.120, -0.040, -0.0030, 0.0030, k("bolt"), bev=0.0003), "bolt")
    path = [(0.0060, -0.150, 0.0), (0.0200, -0.154, -0.0015), (0.0320, -0.158, -0.0060), (0.0400, -0.161, -0.0130)]
    g.add(L.sweep("handle", path, L.section_ellipse(0.0080, 0.0080, 12), k("bolt"), twist_up=(0, 1, 0)), "bolt")
    g.add(L.sphere("knob", 0.0085, (0.0420, -0.162, -0.0185), k("bolt"), 20), "bolt")
    g.add(L.loft("cock", [(-0.212, 0.0060), (-0.210, 0.0094), (-0.196, 0.0094), (-0.192, 0.0070), (-0.183, 0.0070)], k("bolt"), 28),
          "bolt")
    g.spec["grooves"].append({"kinds": [k("bolt")], "axis": (0, 1, 0), "range": (-0.209, -0.197), "pitch": 0.0012, "depth": 0.0002,
                              "box": ((-0.212, -0.195), (-0.02, 0.02))})
    g.add(L.box("safety", -0.0015, 0.0015, -0.206, -0.196, 0.0090, 0.0150, k("bolt"), bev=0.0004), "bolt")
    # full stock, handguard, bands, nose cap, cleaning rod
    heel, toe = (-0.505, -0.040), (-0.512, -0.158)
    bcurve = L.catmull([(heel[0], heel[1] + 0.005), (heel[0] - 0.004, -0.085), (heel[0] - 0.004, -0.125), (toe[0], toe[1] - 0.005)], 6)
    NOSE = 0.640
    st = L.catmull([(NOSE + 0.004, -0.0040), (0.30, -0.0040), (0.040, -0.0050), (-0.170, -0.0050), (-0.178, 0.0035),
                    (-0.240, -0.0050), (-0.300, -0.0150), (heel[0] + 0.02, heel[1] + 0.003), (heel[0] - 0.012, heel[1]),
                    (toe[0] - 0.012, toe[1] - 0.004), (toe[0] + 0.07, toe[1] + 0.030), (-0.300, -0.0920), (-0.240, -0.0640),
                    (-0.200, -0.0560), (-0.120, -0.0505), (-0.030, -0.0430), (0.200, -0.0320), (0.600, -0.0240),
                    (NOSE + 0.004, -0.0200)], 5, closed=True)

    def hw(y, z):
        t = np.clip((-y - 0.25) / 0.24, 0, 1)
        f = np.clip((y + 0.17) / 0.05, 0, 1)
        return 0.0142 + 0.0072 * t * t * (3 - 2 * t) + 0.0010 * f - 0.0012 * np.clip((y - 0.2) / 0.4, 0, 1)
    behind, _front = _stock_cut(heel, toe, bcurve, NOSE)
    stock = _wood("stock", st, hw, k("wood"), 0.0105, [behind, [(NOSE, -0.06), (NOSE + 0.05, -0.06), (NOSE + 0.05, 0.03), (NOSE, 0.03)]],
                  step=0.005)
    g.add(stock)
    g.spec["grain"][k("wood")] = (0, 1, -0.05)
    g.add(_wood("handguard", L.catmull([(0.040, 0.0040), (0.420, 0.0035), (0.424, 0.0080), (0.420, 0.0148), (0.040, 0.0160),
                                         (0.034, 0.0100)], 5, closed=True),
                lambda y, z: np.full_like(y, 0.0128), k("wood"), 0.0075, [], step=0.004))
    for i, (by, ln) in enumerate(((0.250, 0.014), (0.424, 0.018))):
        sec = _hull([(0, 0.002, 0.0158), (0, -0.018, 0.0140)])
        g.add(L.extrude_xz("band%d" % i, sec, by, by + ln, k("band"), bev=0.0006))
        g.add(L.screw("bscr%d" % i, (0.0150, by + ln * 0.5, -0.008), "x+", 0.0016, k("small"), slot_angle=0))
    g.add(L.extrude_xz("nosecap", _hull([(0, 0.0, 0.0108), (0, -0.0125, 0.0110)]), NOSE - 0.016, NOSE + 0.002, k("band"), bev=0.0006))
    g.add(L.loft("rod", [(0.30, 0.0029), (NOSE + 0.030, 0.0029), (NOSE + 0.031, 0.0042), (NOSE + 0.040, 0.0042), (NOSE + 0.042, 0.0034)],
                 k("small"), 16, 0.0, -0.0205))
    _butt_plate(g, bcurve, 2 * hw(np.array([heel[0]]), None)[0] - 0.003, k("butt"))
    _swivel(g, -0.380, -0.112, k("swivel"))
    _swivel(g, 0.257, -0.033, k("swivel"))
    # sights: ladder rear sight (leaf folded), barleycorn front
    yr = 0.075
    g.add(L.box("rsbase", -0.0070, 0.0070, yr - 0.020, yr + 0.016, 0.0120, 0.0160, k("sight"), bev=0.0006))
    leaf = L.box("rsleaf", -0.0055, 0.0055, yr - 0.016, yr + 0.020, 0.0160, 0.0185, k("sight"), bev=0.0004)
    L.boolean(leaf, [L.box("lslot", -0.0012, 0.0012, yr - 0.010, yr + 0.016, 0.01, 0.03, "blued", bev=0)])
    L.finish(leaf)
    g.add(leaf)
    g.add(L.extrude_xz("rsnotch", [(-0.0055, 0.0160), (0.0055, 0.0160), (0.0055, 0.0215, 0.001), (0.0010, 0.0215), (0.0, 0.0200),
                                   (-0.0010, 0.0215), (-0.0055, 0.0215, 0.001)], yr - 0.018, yr - 0.016, k("sight"), bev=0.0002))
    yf = BL - 0.012
    g.add(L.loft("fsband", [(yf - 0.008, 0.0099), (yf + 0.008, 0.0097)], k("sight"), 32))
    g.add(L.extrude("fsblade", [(yf - 0.004, 0.0090), (yf + 0.004, 0.0090), (yf + 0.002, 0.0158, 0.0006), (yf - 0.002, 0.0158, 0.0006)],
                    -0.0010, 0.0010, k("sight"), bev=0.0002))
    g.marker("muzzle", (0, BL, 0))
    g.marker("grip_r", (0, -0.215, -0.032))
    g.marker("grip_l", (0, 0.180, -0.014))
    g.marker("sight_rear", (0, yr - 0.017, 0.0200))
    g.marker("sight_front", (0, yf, 0.0158))
    g.marker("holster_attach", (0, 0.0, -0.010))
    g.marker("shell_eject", (0.012, -0.075, 0.010), fwd=(1.0, -0.2, 0.7))
    g.spec["handling"] += [((-0.26, -0.17), (-0.06, 0.02), 0.4), ((0.10, 0.30), (-0.04, 0.02), 0.3)]
    g.detail_target = (0.0, -0.110, 0.0)


# ============================================================================================ Pellman .22
def build_pellman(g: Gun):
    k = g.k
    BL = 0.560
    br = [(-0.006, 0.0088), (0.020, 0.0088), (0.024, 0.0082), (BL - 0.0010, 0.0068), (BL, 0.0064), (BL, 0.0040), (BL - 0.0008, 0.0031),
          (BL - 0.0010, 0.0030), (BL - 0.06, 0.0030)]
    g.add(L.loft("barrel", br, k("barrel"), 40))
    rec = L.loft("receiver", [(-0.132, 0.0090), (-0.130, 0.0105), (-0.002, 0.0105), (0.0, 0.0098)], k("frame"), 40)
    L.boolean(rec, [L.box("port", 0.0, 0.03, -0.090, -0.040, -0.004, 0.006, "blued", bev=0),
                    L.box("hslot", 0.0, 0.03, -0.122, -0.085, -0.0020, 0.0020, "blued", bev=0),
                    L.loft("bway", [(-0.14, 0.0078), (-0.03, 0.0078)], "blued", 28)])
    L.bevel(rec, 0.0003, 1, 40)
    L.finish(rec)
    g.add(rec)
    TZ = -0.0140
    g.add(L.loft("tube", [(0.010, 0.0050), (0.470, 0.0050)], k("tube"), 24, 0, TZ))
    g.add(L.loft("tcap", [(0.470, 0.0056), (0.490, 0.0056), (0.492, 0.0040)], k("tube"), 24, 0, TZ))
    g.spec["grooves"].append({"kinds": [k("tube")], "axis": (0, 1, 0), "range": (0.472, 0.489), "pitch": 0.0010, "depth": 0.00015,
                              "box": ((0.47, 0.49), (TZ - 0.01, TZ + 0.01))})
    g.add(L.extrude_xz("tband", _hull([(0, 0.0, 0.0078), (0, TZ, 0.0061)]), 0.440, 0.448, k("small"), bev=0.0004))
    _guard(g, [(-0.068, -0.0270), (-0.069, -0.0370), (-0.078, -0.0470), (-0.098, -0.0480), (-0.110, -0.0390), (-0.112, -0.0290)],
           k("small"), w=0.0070, h=0.0028)
    _trigger(g, (-0.084, -0.0220), 0.020, k("small"), width=0.0018)
    g.part("bolt", (0, -0.090, 0), {"type": "bolt", "axis": (0, -1, 0), "open": 0.052, "rot_axis": (0, 1, 0), "rot": -70.0})
    g.add(L.loft("boltbody", [(-0.140, 0.0076), (-0.040, 0.0076)], k("bolt"), 28), "bolt")
    g.add(L.sweep("handle", [(0.0050, -0.105, 0.0), (0.0180, -0.106, 0.0), (0.0260, -0.107, -0.002)], L.section_ellipse(0.0055, 0.0055, 10),
                  k("bolt"), twist_up=(0, 1, 0)), "bolt")
    g.add(L.sphere("knob", 0.0055, (0.0290, -0.107, -0.003), k("bolt"), 16), "bolt")
    g.add(L.loft("cock", [(-0.156, 0.0050), (-0.154, 0.0085), (-0.144, 0.0085), (-0.140, 0.0060)], k("bolt"), 24), "bolt")
    g.spec["grooves"].append({"kinds": [k("bolt")], "axis": (0, 1, 0), "range": (-0.153, -0.145), "pitch": 0.0010, "depth": 0.00018,
                              "box": ((-0.157, -0.143), (-0.02, 0.02))})
    heel, toe = (-0.430, -0.034), (-0.434, -0.138)
    bcurve = L.catmull([(heel[0], heel[1] + 0.004), (heel[0] - 0.004, -0.075), (heel[0] - 0.003, -0.110), (toe[0], toe[1] - 0.004)], 6)
    FE = 0.300
    st = L.catmull([(FE + 0.010, -0.0020), (0.100, -0.0025), (-0.128, -0.0030), (-0.135, 0.0040), (-0.200, -0.0040),
                    (-0.250, -0.0120), (heel[0] + 0.02, heel[1] + 0.003), (heel[0] - 0.012, heel[1]), (toe[0] - 0.012, toe[1] - 0.004),
                    (toe[0] + 0.06, toe[1] + 0.024), (-0.280, -0.0780), (-0.200, -0.0480), (-0.150, -0.0350), (-0.060, -0.0270),
                    (0.100, -0.0255), (FE, -0.0235), (FE + 0.011, -0.0120)], 5, closed=True)

    def hw(y, z):
        t = np.clip((-y - 0.20) / 0.22, 0, 1)
        return 0.0118 + 0.0072 * t * t * (3 - 2 * t)
    behind, _ = _stock_cut(heel, toe, bcurve, FE)
    g.add(_wood("stock", st, hw, k("wood"), 0.0090, [behind], step=0.0045))
    g.spec["grain"][k("wood")] = (0, 1, -0.06)
    _butt_plate(g, bcurve, 2 * hw(np.array([heel[0]]), None)[0] - 0.003, k("butt"))
    g.spec["grooves"].append({"kinds": [k("butt")], "axis": (0, 0.1, 1), "range": (-0.2, 0.2), "pitch": 0.0025, "depth": 0.0004})
    yr = 0.120
    g.add(L.box("rsbase", -0.0035, 0.0035, yr - 0.008, yr + 0.006, 0.0068, 0.0088, k("sight"), bev=0.0003))
    g.add(L.extrude_xz("rsleaf", [(-0.0070, 0.0080), (0.0070, 0.0080), (0.0070, 0.0120, 0.0015), (0.0012, 0.0120), (0.0, 0.0105),
                                  (-0.0012, 0.0120), (-0.0070, 0.0120, 0.0015)], yr, yr + 0.0012, k("sight"), bev=0.0002))
    yf = BL - 0.010
    g.add(L.extrude("fsblade", [(yf - 0.005, 0.0060), (yf + 0.004, 0.0060), (yf + 0.002, 0.0098, 0.0006), (yf - 0.002, 0.0098, 0.0006)],
                    -0.0008, 0.0008, k("sight"), bev=0.0002))
    g.add(L.sphere("bead", 0.0013, (0, yf, 0.0102), k("sight"), 12))
    g.marker("muzzle", (0, BL, 0))
    g.marker("grip_r", (0, -0.185, -0.024))
    g.marker("grip_l", (0, 0.150, -0.012))
    g.marker("sight_rear", (0, yr, 0.0105))
    g.marker("sight_front", (0, yf, 0.0110))
    g.marker("holster_attach", (0, 0.0, -0.008))
    g.marker("shell_eject", (0.011, -0.065, 0.0), fwd=(1.0, -0.2, 0.6))
    g.spec["handling"] += [((-0.21, -0.14), (-0.05, 0.02), 0.4)]
    g.detail_target = (0.0, -0.090, -0.005)


# ============================================================================================ Vance rolling block
def build_vance(g: Gun):
    k = g.k
    BL = 0.760
    br = [(-0.004, 0.0135, "o"), (BL - 0.0012, 0.0116, "o"), (BL, 0.0112, "o"), (BL, 0.0075, "o"), (BL - 0.0010, 0.0060),
          (BL - 0.0012, 0.0058), (BL - 0.06, 0.0058)]
    g.add(L.loft("barrel", br, k("barrel"), 32))
    W = 0.0138
    prof = [(0.0, -0.0300, 0.003), (0.0, 0.0160, 0.003), (-0.0100, 0.0160, 0.002), (-0.0140, 0.0020, 0.003), (-0.0660, 0.0020, 0.003),
            (-0.0720, 0.0100, 0.003), (-0.0860, 0.0080, 0.004), (-0.0880, -0.0200, 0.004), (-0.0800, -0.0320, 0.006)]
    rec = L.extrude("receiver", prof, -W, W, k("frame"), bev=0.0007)
    L.boolean(rec, [L.box("bslot", -0.0090, 0.0090, -0.072, -0.006, -0.020, 0.03, "blued", bev=0)])
    L.bevel(rec, 0.0004, 1, 40)
    L.finish(rec)
    g.add(rec)
    for sx, ax in ((W + 0.0001, "x+"), (-W - 0.0001, "x-")):
        g.add(L.pin("bpin%s" % ax, (sx, -0.0180, -0.0120), "X", 0.0042, 0.0012, k("small")))
        g.add(L.pin("hpin%s" % ax, (sx, -0.0560, -0.0160), "X", 0.0042, 0.0012, k("small")))
        g.add(L.screw("sscr", (sx, -0.0400, -0.0240), ax, 0.0020, k("small"), slot_angle=30))
    g.add(L.extrude("utang", [(-0.086, 0.0080), (-0.160, -0.0010, 0.003), (-0.161, -0.0036), (-0.086, 0.0054)], -0.0062, 0.0062,
                    k("frame"), bev=0.0006))
    g.add(L.extrude("ltang", [(-0.082, -0.0300), (-0.175, -0.0500, 0.003), (-0.176, -0.0474), (-0.082, -0.0274)], -0.0066, 0.0066,
                    k("frame"), bev=0.0006))
    _guard(g, [(-0.028, -0.0310), (-0.029, -0.0440), (-0.039, -0.0570), (-0.060, -0.0590), (-0.074, -0.0480), (-0.076, -0.0340)], k("frame"))
    _trigger(g, (-0.046, -0.0300), 0.022, k("small"))
    # tang peep sight (staff up)
    g.add(L.box("tsbase", -0.0045, 0.0045, -0.122, -0.104, 0.0000, 0.0032, k("sight"), bev=0.0004))
    g.add(L.box("tsstaff", -0.0022, 0.0022, -0.114, -0.110, 0.0030, 0.0420, k("sight"), bev=0.0004))
    g.add(L.cyl("tspeep", 0.0055, -0.1130, -0.1110, k("sight"), 24, x0=0.0, z0=0.0400))
    g.spec["grooves"].append({"kinds": [k("sight")], "axis": (0, 0, 1), "range": (0.006, 0.034), "pitch": 0.0015, "depth": 0.0002,
                              "box": ((-0.115, -0.109), (0.004, 0.036))})
    # breechblock (part): rolls back on its pin, thumb spur on top
    g.part("breech", (0, -0.0180, -0.0120), {"type": "rot", "axis": (1, 0, 0), "open": 68.0})
    bb = [(-0.0045, -0.0230, 0.006), (-0.0030, 0.0060, 0.002), (-0.0080, 0.0130, 0.003), (-0.0200, 0.0175, 0.004), (-0.0310, 0.0270, 0.003),
          (-0.0350, 0.0250, 0.002), (-0.0300, 0.0130, 0.005), (-0.0280, -0.0060, 0.007), (-0.0180, -0.0255, 0.008)]
    g.add(L.extrude("breech_b", bb, -0.0086, 0.0086, k("breech"), bev=0.0006), "breech")
    g.spec["grooves"].append({"kinds": [k("breech")], "axis": (0, -0.6, 0.8), "range": (-0.04, 0.04), "pitch": 0.0011, "depth": 0.0002,
                              "box": ((-0.036, -0.026), (0.020, 0.029))})
    # hammer (part)
    g.part("hammer", (0, -0.0560, -0.0160), {"type": "rot", "axis": (1, 0, 0), "open": 55.0, "half": 20.0})
    hb = [(-0.0310, -0.0200, 0.004), (-0.0300, 0.0080, 0.004), (-0.0360, 0.0150, 0.004), (-0.0480, 0.0200, 0.006), (-0.0640, 0.0300, 0.004),
          (-0.0760, 0.0350, 0.003), (-0.0790, 0.0325, 0.002), (-0.0700, 0.0240, 0.004), (-0.0610, 0.0120, 0.006), (-0.0640, -0.0120, 0.006),
          (-0.0560, -0.0250, 0.007), (-0.0420, -0.0270, 0.006)]
    g.add(L.extrude("hammer_b", hb, -0.0080, 0.0080, k("hammer"), bev=0.0006), "hammer")
    g.spec["checker"].append({"kinds": [k("hammer")], "normal": (0, -0.4, 0.9), "min_dot": 0.45, "center": (-0.0730, 0.0335),
                              "radii": (0.006, 0.007), "angle": 25.0, "pitch": 0.0011, "depth": 0.00025, "border": False, "shape": "box"})
    # stock (straight wrist, shotgun butt) and schnabel fore-end
    heel, toe = (-0.405, -0.040), (-0.410, -0.152)
    bcurve = L.catmull([(heel[0], heel[1] + 0.005), (heel[0] - 0.004, -0.085), (heel[0] - 0.003, -0.122), (toe[0], toe[1] - 0.005)], 6)
    st = L.catmull([(-0.080, 0.0080), (-0.160, -0.0040), (-0.210, -0.0120), (heel[0] + 0.02, heel[1] + 0.003), (heel[0] - 0.012, heel[1]),
                    (toe[0] - 0.012, toe[1] - 0.004), (toe[0] + 0.07, toe[1] + 0.028), (-0.230, -0.0700), (-0.180, -0.0520),
                    (-0.130, -0.0420), (-0.080, -0.0300)], 6, closed=True)

    def hw(y, z):
        t = np.clip((-y - 0.15) / 0.22, 0, 1)
        return 0.0136 + 0.0072 * t * t * (3 - 2 * t)
    behind, _ = _stock_cut(heel, toe, bcurve, 0.0)
    g.add(_wood("stock", st, hw, k("wood"), 0.0100, [behind, [(-0.087, -0.08), (-0.03, -0.08), (-0.03, 0.03), (-0.087, 0.03)]], step=0.0045))
    g.spec["grain"][k("wood")] = (0, 1, -0.1)
    g.spec["checker"].append({"kinds": [k("wood")], "normal": (1, 0, 0), "min_dot": 0.55, "center": (-0.135, -0.024), "radii": (0.026, 0.014),
                              "angle": -14.0, "pitch": 0.0018, "depth": 0.0003, "border": True})
    _butt_plate(g, bcurve, 2 * hw(np.array([heel[0]]), None)[0] - 0.003, k("butt"))
    FE = 0.300
    fe = L.catmull([(-0.004, 0.0030), (FE * 0.5, 0.0030), (FE - 0.010, 0.0025), (FE + 0.002, -0.0020), (FE + 0.004, -0.0150),
                    (FE - 0.006, -0.0300), (FE - 0.024, -0.0260), (FE * 0.5, -0.0255), (-0.004, -0.0285)], 6, closed=True)
    g.add(_wood("fore", fe, lambda y, z: np.full_like(y, 0.0132), k("fore"), 0.009, [[(0.001, -0.06), (0.001, 0.04), (-0.03, 0.04), (-0.03, -0.06)]]))
    g.spec["grain"][k("fore")] = (0, 1, 0)
    g.add(L.screw("fescr", (0.0133, 0.150, -0.012), "x+", 0.0020, k("small")))
    # sights on the barrel: ladder rear (raised), blade front
    yr = 0.110
    g.add(L.box("rsbase", -0.0060, 0.0060, yr - 0.018, yr + 0.010, 0.0130, 0.0160, k("sight"), bev=0.0005))
    g.add(L.extrude_xz("rsleaf", [(-0.0050, 0.0150), (0.0050, 0.0150), (0.0050, 0.0300, 0.0012), (0.0010, 0.0300), (0.0, 0.0285),
                                  (-0.0010, 0.0300), (-0.0050, 0.0300, 0.0012)], yr - 0.006, yr - 0.0045, k("sight"), bev=0.0002))
    yf = BL - 0.014
    g.add(L.box("fsbase", -0.0040, 0.0040, yf - 0.007, yf + 0.007, 0.0112, 0.0130, k("sight"), bev=0.0003))
    g.add(L.extrude("fsblade", [(yf - 0.0045, 0.0125), (yf + 0.0045, 0.0125), (yf + 0.0030, 0.0185, 0.0012), (yf - 0.0025, 0.0185, 0.001)],
                    -0.0008, 0.0008, k("sight"), bev=0.0002))
    g.marker("muzzle", (0, BL, 0))
    g.marker("grip_r", (0, -0.140, -0.030))
    g.marker("grip_l", (0, 0.160, -0.014))
    g.marker("sight_rear", (0, -0.112, 0.0400))
    g.marker("sight_front", (0, yf, 0.0185))
    g.marker("holster_attach", (0, 0.0, -0.008))
    g.marker("shell_eject", (0, -0.006, 0.004), fwd=(0.15, -1.0, 0.8))
    g.spec["handling"] += [((-0.16, -0.09), (-0.05, 0.02), 0.4), ((0.05, FE), (-0.03, 0.0), 0.3)]
    g.detail_target = (0.0, -0.045, 0.0)


BUILDERS = {"bowden_bolt": build_bowden, "pellman_varmint": build_pellman, "vance_rolling": build_vance}
