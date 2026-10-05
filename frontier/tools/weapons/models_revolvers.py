"""Revolvers: Lockhart .44 Single Action (solid frame, loading gate, ejector rod), Sheridan Double Action (top-break
auto-ejector), Talbot Pocket Pistol (bird's-head pocket double action). Original designs; period mechanisms."""
import math

import numpy as np

from mathutils import Vector

import gun_lib as L
from gun_rig import FINISHES, Gun, bullet_nose, cartridge_rim

FINISHES["lockhart_sa"] = {
    "standard": {"frame": "case", "barrel": "blued", "cyl": "blued", "hammer": "case", "small": "blued",
                 "guard": "blued", "grip": "walnut_grip", "pin": "blued"},
    "nickel": {"frame": "nickel", "barrel": "nickel", "cyl": "nickel", "hammer": "nickel", "small": "nickel",
               "guard": "nickel", "grip": "rubber", "pin": "nickel"},
}


def _chamber_xz(cyl_z, rad, ang_deg):
    a = math.radians(ang_deg)
    return rad * math.cos(a), cyl_z + rad * math.sin(a)


def revolver_cylinder(g, name, part, y0, y1, cz, R, ch_r, ch_rad, n_ch=6, flutes=True, flute_r=0.0042,
                      notch=True, kind="cyl", rims=True, nose_len=0.008, phase=90.0, rim_r=None):
    """Cylinder body with chambers, flutes, bolt notches, plus loaded cartridges (rims rear, lead noses front)."""
    c = 0.0009
    body = L.loft(name, [(y0, R - c), (y0 + c, R), (y1 - c * 1.2, R), (y1, R - c * 1.1)], g.k(kind), 72, 0.0, cz)
    cut = []
    for i in range(n_ch):
        x, z = _chamber_xz(cz, ch_rad, phase + 360.0 / n_ch * i)
        cut.append(L.loft("ch", [(y0 - 0.002, ch_r), (y1 + 0.002, ch_r)], "blued", 28, x, z))
        if flutes:
            fx, fz = _chamber_xz(cz, R + flute_r * 0.22, phase + 360.0 / n_ch * (i + 0.5))
            fl = []
            ya, yb = y0 + (y1 - y0) * 0.34, y1 - (y1 - y0) * 0.1
            for k in range(7):
                a = k / 6 * math.pi / 2
                fl.append((ya - flute_r * math.cos(a) + flute_r * 0.0, flute_r * math.sin(a) + 1e-5))
            fl = [(ya - flute_r + flute_r * (1 - math.cos(k / 6 * math.pi / 2)), flute_r * math.sin(k / 6 * math.pi / 2) + 1e-5) for k in range(7)]
            fl += [(yb + flute_r * math.sin(k / 6 * math.pi / 2), flute_r * math.cos(k / 6 * math.pi / 2) + 1e-5) for k in range(7)]
            cut.append(L.loft("fl", fl, "blued", 20, fx, fz))
        if notch:
            nx, nz = _chamber_xz(cz, R, phase + 360.0 / n_ch * i + 180.0 / n_ch * 0.0)
            # notch sits between chambers' outer surface: small box aligned tangentially
            ang = phase + 360.0 / n_ch * i
            bx = L.box("nt", -0.0015, 0.0015, y0 + 0.0028, y0 + 0.0065, -0.0013, 0.0013, "blued", bev=0)
            L.transform(bx, L.rot_y(-(ang - 90.0)))
            L.move(bx, (nx, 0, nz))
            cut.append(bx)
    cut.append(L.loft("pin", [(y0 - 0.002, 0.0028), (y1 + 0.002, 0.0028)], "blued", 20, 0, cz))
    L.boolean(body, cut)
    L.bevel(body, 0.00035, 2, 35)
    L.finish(body)
    g.add(body, part)
    if rims:
        rr = rim_r or ch_r * 1.12
        for i in range(n_ch):
            x, z = _chamber_xz(cz, ch_rad, phase + 360.0 / n_ch * i)
            g.add(cartridge_rim("rim%d" % i, g.k("cart"), (x, y0, z), rr, 0.0011, ch_r * 0.36), part, uvs=0.3)
            g.add(bullet_nose("nose%d" % i, g.k("lead"), (x, 0, z), ch_r * 0.93, nose_len, y1 - 0.0012), part, uvs=0.4)
            # case mouth ring just inside the chamber
            g.add(L.loft("mouth%d" % i, [(y1 - 0.0045, ch_r * 0.99), (y1 - 0.0026, ch_r * 0.99), (y1 - 0.0026, ch_r * 0.9)],
                         g.k("cart"), 24, x, z, cap0=False, cap1=False), part, uvs=0.3)
    return body


def _ejector(g, FF, CZ, rx, rz):
    k = g.k
    hull = []
    for i in range(20):
        a = math.tau * i / 20
        hull.append((rx + 0.0039 * math.cos(a), rz + 0.0039 * math.sin(a)))
    for i in range(14):
        a = math.tau * i / 14
        hull.append((0.0058 + 0.0016 * math.cos(a), -0.0098 + 0.0016 * math.sin(a)))
    from scipy.spatial import ConvexHull
    hv = ConvexHull(hull).vertices
    sec = [hull[i] for i in hv]
    hous = L.extrude_xz("ejhousing", sec, FF + 0.0004, 0.1560, k("barrel"), bev=0.0007, bseg=3)
    bore = L.loft("ejbore", [(FF - 0.01, 0.0021), (0.1485, 0.0021)], "blued", 16, rx, rz)
    out = Vector((rx, 0, rz)).normalized()
    sl = L.box("ejslot", -0.0013, 0.0013, 0.0780, 0.1480, -0.012, 0.0, "blued", bev=0)
    L.transform(sl, L.rot_y(-math.degrees(math.atan2(out.x, -out.z))))
    L.move(sl, (rx, 0, rz))
    L.boolean(hous, [bore, sl])
    L.finish(hous)
    g.add(hous)
    g.add(L.screw("ejscrew", (0.0098, 0.1250, -0.0140), "x+", 0.0021, k("small"), slot_angle=30))
    g.part("ejector_rod", (rx, 0.12, rz), {"type": "slide", "axis": (0, -1, 0), "open": 0.038})
    g.add(L.loft("ejrod", [(0.050, 0.0017), (0.1500, 0.0017)], k("pin"), 14, rx, rz), "ejector_rod")
    knob = L.loft("ejknob", [(0.0, 0.0034), (0.0008, 0.0036), (0.0028, 0.0036), (0.0036, 0.0028)], k("pin"), 20)
    L.transform(knob, L.rot_x(-90))
    L.transform(knob, L.rot_y(-math.degrees(math.atan2(out.x, -out.z)) + 0.0))
    L.move(knob, (rx + out.x * 0.0028, 0.1430, rz + out.z * 0.0030))
    g.add(knob, "ejector_rod")


LOCKHART = {"barrel": 0.189, "ejector": True, "grip": "plow", "chambers": 6, "flutes": True, "scale": 1.0}
TALBOT = {"barrel": 0.064, "ejector": False, "grip": "bird", "chambers": 5, "flutes": True, "scale": 0.84}


def build_lockhart(g: Gun, P=None):
    P = dict(LOCKHART, **(P or {}))
    CZ, CR = -0.0132, 0.0210
    CY0, CY1 = 0.0012, 0.0420
    FF = 0.0600                      # frame front
    BY1 = FF + P["barrel"]          # muzzle
    DS = BY1 - 0.2490
    W = 0.0115                       # frame half width
    k = g.k
    # ---------------- frame
    prof = [(FF, 0.0090, 0.002), (FF, -0.0190, 0.003), (FF - 0.0160, -0.0405, 0.012), (-0.0072, -0.0405),
            (-0.0072, 0.0090)]
    frame = L.extrude("frame", prof, -W, W, k("frame"), bev=0.0006, bseg=2)
    win = L.box("win", -0.03, 0.03, 0.0004, 0.0438, -0.0352, 0.0200, "blued", bev=0)
    L.boolean(frame, [win])
    L.finish(frame)
    g.add(frame)
    # rear of the frame (hammer housing): rounded, a little narrower, tapering into the grip straps
    rear = L.fillet([(-0.0040, 0.0112), (-0.0085, 0.0112, 0.003), (-0.0165, 0.0045, 0.006), (-0.0196, -0.0100, 0.005),
                     (-0.0162, -0.0340, 0.005), (-0.0090, -0.0405, 0.003), (-0.0040, -0.0405)])
    fr = L.pillow("frame_rear", rear, lambda y, z: 0.0104 + 0.0010 * np.clip((y + 0.016) / 0.010, 0, 1), k("frame"),
                  round_r=0.0032, step=0.0016)
    slot = L.box("hslot", -0.0049, 0.0049, -0.0260, -0.0050, -0.0240, 0.0200, "blued", bev=0)
    fpin = L.cyl("fph", 0.0011, -0.012, 0.002, "blued", 12)
    L.boolean(fr, [slot])
    L.finish(fr, math.radians(60))
    g.add(fr)
    # front ring around the barrel shank (rounded top of the frame front)
    g.add(L.loft("fring", [(0.0436, 0.0105), (0.0440, 0.0118), (FF - 0.0006, 0.0118), (FF, 0.0110)], k("frame"), 40))
    # recoil shield with the loading-gate notch
    shield = L.loft("shield", [(-0.0068, 0.0185), (-0.0060, 0.0198), (0.0003, 0.0198)], k("frame"), 64, 0.0, CZ)
    gx0, gz0, gz1 = 0.0068, -0.0285, -0.0105
    notch = L.box("gnotch", gx0, 0.03, -0.02, 0.02, gz0, gz1, "blued", bev=0)
    L.boolean(shield, [notch, fpin])
    L.bevel(shield, 0.0004, 2, 35)
    L.finish(shield)
    g.add(shield)
    # top strap with sighting groove and rear notch
    sec = [(-0.0080, 0.0084), (0.0080, 0.0084), (0.0080, 0.0112, 0.0022), (0.0040, 0.0131, 0.003), (-0.0040, 0.0131, 0.003),
           (-0.0080, 0.0112, 0.0022)]
    strap = L.extrude_xz("topstrap", sec, -0.0075, FF - 0.0002, k("frame"), bev=0.0004)
    groove = L.box("grv", -0.0011, 0.0011, -0.02, 0.07, 0.0122, 0.02, "blued", bev=0)
    rnotch = L.box("rn", -0.0016, 0.0016, -0.012, -0.0035, 0.0108, 0.02, "blued", bev=0)
    L.boolean(strap, [groove, rnotch])
    L.finish(strap)
    g.add(strap)
    # ---------------- barrel (bore visible at the muzzle)
    br = [(0.0440, 0.0074), (0.0585, 0.0074), (0.0585, 0.0089), (0.0600, 0.0088), (FF + (BY1 - FF) * 0.33, 0.0084), (BY1 - 0.0012, 0.0079),
          (BY1, 0.0074), (BY1, 0.0064), (BY1 - 0.0010, 0.0056), (BY1 - 0.0012, 0.0054), (BY1 - 0.090, 0.0054)]
    g.add(L.loft("barrel", br, k("barrel"), 56))
    # muzzle-end front sight (half-moon blade)
    fs = [(0.2330 + DS, 0.0076), (0.2468 + DS, 0.0072), (0.2464 + DS, 0.0098, 0.0015), (0.2425 + DS, 0.0124, 0.0025),
          (0.2378 + DS, 0.0112, 0.002)]
    g.add(L.extrude("fsight", fs, -0.0009, 0.0009, k("barrel"), bev=0.0002))
    # ---------------- ejector rod housing (right side, under the barrel) and rod
    rx, rz = _chamber_xz(CZ, 0.0132, -30.0)
    if P["ejector"]:
        _ejector(g, FF, CZ, rx, rz)
    # ---------------- base pin
    g.add(L.loft("basepin", [(0.0300, 0.0026), (FF + 0.0004, 0.0026), (FF + 0.0004, 0.0035), (FF + 0.0045, 0.0035),
                             (FF + 0.0052, 0.0028)], k("pin"), 24, 0.0, CZ))
    g.spec["grooves"].append({"kinds": [k("pin")], "axis": (0, 1, 0), "range": (FF + 0.0007, FF + 0.0042), "pitch": 0.0007,
                              "depth": 0.0002, "box": ((FF, FF + 0.006), (CZ - 0.004, CZ + 0.004))})
    g.add(L.screw("latch", (-W - 0.0001, 0.0530, CZ - 0.0045), "x-", 0.0024, k("small"), slot_angle=10))
    # ---------------- loading gate (part): a piece of the recoil shield, hinged at its bottom edge along Y
    gate = L.loft("gate", [(-0.0066, 0.0183), (-0.0058, 0.0196), (0.0001, 0.0196)], k("frame"), 64, 0.0, CZ)
    keep = L.box("gkeep", gx0 + 0.0003, 0.03, -0.02, 0.02, gz0 + 0.0003, gz1 - 0.0003, "blued", bev=0)
    L.boolean(gate, keep, op="INTERSECT")
    L.bevel(gate, 0.0003, 2, 35)
    L.finish(gate)
    g.part("loading_gate", (0.0150, -0.003, gz0 + 0.0008), {"type": "rot", "axis": (0, 1, 0), "open": 85.0})
    g.add(gate, "loading_gate")
    # ---------------- cylinder (part)
    g.part("cylinder", (0, 0.02, CZ), {"type": "rot", "axis": (0, 1, 0), "open": 360.0 / P["chambers"], "steps": P["chambers"]})
    revolver_cylinder(g, "cyl", "cylinder", CY0, CY1, CZ, CR, 0.0058, 0.0132, n_ch=P["chambers"], flutes=P["flutes"])
    # ---------------- hammer (part)
    hp = (-0.0125, -0.0150)
    hprof = [(-0.0068, -0.0090, 0.002), (-0.0068, 0.0040, 0.001), (-0.0084, 0.0088, 0.003), (-0.0140, 0.0128, 0.006),
             (-0.0220, 0.0182, 0.006), (-0.0292, 0.0214, 0.003), (-0.0318, 0.0196, 0.002), (-0.0300, 0.0150, 0.004),
             (-0.0250, 0.0105, 0.006), (-0.0208, 0.0040, 0.006), (-0.0192, -0.0120, 0.004), (-0.0125, -0.0218, 0.005),
             (-0.0078, -0.0182, 0.003)]
    g.part("hammer", (0, hp[0], hp[1]), {"type": "rot", "axis": (1, 0, 0), "open": 50.0, "half": 22.0})
    hb = L.extrude("hammer_b", hprof, -0.0041, 0.0041, k("hammer"), bev=0.0005)
    # the spur is a little wider than the body (thumb piece)
    L.deform(hb, lambda co: co + np.stack([co[:, 0] * 0.25 * np.clip((-co[:, 1] - 0.020) / 0.008, 0, 1), co[:, 0] * 0, co[:, 0] * 0], 1))
    g.add(hb, "hammer")
    g.add(L.loft("fpin", [(-0.0070, 0.0011), (-0.0058, 0.0008), (-0.0056, 0.0004)], k("hammer"), 12, 0, 0.0005), "hammer")
    g.spec["checker"].append({"kinds": [k("hammer")], "normal": (0, -0.5, 0.86), "min_dot": 0.45, "center": (-0.0275, 0.0195),
                              "radii": (0.0050, 0.006), "angle": 30.0, "pitch": 0.0010, "depth": 0.00025, "border": False,
                              "shape": "box"})
    # ---------------- trigger (part)
    tpv = (0.0105, -0.0372)
    g.part("trigger", (0, tpv[0], tpv[1]), {"type": "rot", "axis": (1, 0, 0), "open": -14.0})
    tprof = [(0.0125, -0.0340), (0.0128, -0.0420, 0.002), (0.0118, -0.0500, 0.005), (0.0092, -0.0566, 0.004),
             (0.0064, -0.0598, 0.0014), (0.0046, -0.0584, 0.0014), (0.0068, -0.0530, 0.005), (0.0084, -0.0440, 0.003),
             (0.0085, -0.0340)]
    g.add(L.extrude("trigger_b", tprof, -0.0021, 0.0021, k("small"), bev=0.0004), "trigger")
    g.spec["grooves"].append({"kinds": [k("small")], "axis": (0, 0.45, -1), "range": (0.020, 0.060), "pitch": 0.0009,
                              "depth": 0.00012, "box": ((0.008, 0.0135), (-0.058, -0.041))})
    # ---------------- grip frame (back strap + front strap) and the trigger guard bow
    if P["grip"] == "bird":
        outline = L.catmull([(-0.0188, -0.0070), (-0.0280, -0.0250), (-0.0390, -0.0460), (-0.0470, -0.0700), (-0.0478, -0.0880),
                             (-0.0420, -0.1000), (-0.0320, -0.1030), (-0.0230, -0.0960), (-0.0190, -0.0800), (-0.0140, -0.0620),
                             (-0.0108, -0.0490), (-0.0094, -0.0400), (-0.0150, -0.0330)], 5, closed=True)
        wood = L.catmull([(-0.0172, -0.0240), (-0.0262, -0.0290), (-0.0372, -0.0470), (-0.0450, -0.0700), (-0.0456, -0.0870),
                          (-0.0408, -0.0975), (-0.0322, -0.1002), (-0.0245, -0.0940), (-0.0206, -0.0790), (-0.0156, -0.0615),
                          (-0.0122, -0.0482), (-0.0112, -0.0400), (-0.0150, -0.0345)], 5, closed=True)
    else:
        outline = L.catmull([(-0.0188, -0.0070), (-0.0272, -0.0250), (-0.0378, -0.0450), (-0.0468, -0.0680), (-0.0520, -0.0920),
                             (-0.0540, -0.1120), (-0.0520, -0.1215), (-0.0420, -0.1258), (-0.0290, -0.1272), (-0.0222, -0.1250),
                             (-0.0212, -0.1060), (-0.0186, -0.0840), (-0.0148, -0.0640), (-0.0112, -0.0500), (-0.0094, -0.0400),
                             (-0.0150, -0.0330)], 5, closed=True)
        wood = L.catmull([(-0.0172, -0.0240), (-0.0256, -0.0290), (-0.0362, -0.0462), (-0.0452, -0.0682), (-0.0505, -0.0920),
                          (-0.0524, -0.1112), (-0.0508, -0.1200), (-0.0415, -0.1242), (-0.0292, -0.1256), (-0.0234, -0.1236),
                          (-0.0226, -0.1060), (-0.0199, -0.0840), (-0.0161, -0.0640), (-0.0125, -0.0492), (-0.0112, -0.0400),
                          (-0.0150, -0.0345)], 5, closed=True)

    gf = L.pillow("gripframe", outline, 0.0097, k("guard"), round_r=0.0055, step=0.0024)
    g.add(gf)

    def ghw(y, z):
        t = (z + 0.040) / -0.085
        return 0.0128 + 0.0034 * (1 - (2 * t - 1.1) ** 2).clip(0, 1)
    gw = L.pillow("grip", wood, ghw, k("grip"), round_r=0.0068, step=0.0022)
    g.add(gw)
    g.spec["grain"][k("grip")] = (0, 0.3, -1.0)
    g.spec["grain_center"][k("grip")] = (0.04, -0.03, -0.08)
    gpath = L.catmull([(0.0300, -0.0398), (0.0290, -0.0480), (0.0235, -0.0590), (0.0130, -0.0672), (0.0010, -0.0688),
                       (-0.0080, -0.0640), (-0.0118, -0.0560), (-0.0120, -0.0470), (-0.0108, -0.0410)], 5)
    g.add(L.sweep("guard", L.path_yz(gpath), L.section_rect(0.0078, 0.0036, 0.0015), k("guard")))
    # screws: hammer pivot (both sides), trigger, bolt; strap screws
    for sx, ax in ((W + 0.0001, "x+"), (-W - 0.0001, "x-")):
        g.add(L.screw("hscrew", (sx, hp[0], hp[1]), ax, 0.0026, k("small"), slot_angle=60 if sx > 0 else 20))
        g.add(L.screw("tscrew", (sx, tpv[0], tpv[1]), ax, 0.0022, k("small"), slot_angle=100 if sx > 0 else 45))
    g.add(L.screw("bscrew", (-W - 0.0001, 0.0220, -0.0360), "x-", 0.0022, k("small"), slot_angle=75))
    g.add(L.screw("strapscr", (0, -0.0190, 0.0040), "y-", 0.0020, k("small"), slot_angle=0))
    g.add(L.screw("guardscr", (0, 0.0330, -0.0406), "z-", 0.0020, k("small"), slot_angle=0))
    # wear regions
    g.spec["handling"] += [((BY1 - 0.05, BY1), (-0.02, 0.02), 0.35), ((-0.03, 0.0), (-0.01, 0.025), 0.4)]
    # ---------------- markers
    g.marker("muzzle", (0, BY1, 0))
    g.marker("grip_r", (0, -0.0300, -0.0720))
    g.marker("grip_l", (-0.0130, -0.0260, -0.0900))
    g.marker("sight_rear", (0, -0.0050, 0.0123))
    g.marker("sight_front", (0, 0.2425 + DS, 0.0124))
    g.marker("holster_attach", (0, 0.0200, CZ))
    g.marker("shell_eject", (rx + 0.006, -0.002, rz), fwd=(0.35, -1.0, -0.25))
    g.length_hint = 0.33
    g.detail_target = (0.004, 0.0, -0.012)
    if P["scale"] != 1.0:
        g.scale_all(P["scale"])


FINISHES["talbot_pocket"] = {
    "standard": {"frame": "blued", "barrel": "blued", "cyl": "blued", "hammer": "case", "small": "blued",
                 "guard": "blued", "grip": "walnut_grip", "pin": "blued"},
    "nickel": {"frame": "nickel", "barrel": "nickel", "cyl": "nickel", "hammer": "nickel", "small": "nickel",
               "guard": "nickel", "grip": "rubber", "pin": "nickel"},
}
FINISHES["sheridan_dao"] = {
    "standard": {"frame": "nickel", "barrel": "nickel", "cyl": "nickel", "hammer": "nickel", "small": "nickel",
                 "guard": "nickel", "grip": "rubber", "pin": "nickel"},
    "blued": {"frame": "blued", "barrel": "blued", "cyl": "blued", "hammer": "case", "small": "blued",
              "guard": "blued", "grip": "walnut_grip", "pin": "blued"},
}


def build_talbot(g: Gun):
    build_lockhart(g, TALBOT)


def build_sheridan(g: Gun):
    """Top-break double action: the barrel, top strap, latch and cylinder tilt down on a hinge at the front of the
    frame; the extractor star throws all cases at once."""
    k = g.k
    CZ, CR = -0.0125, 0.0195
    CY0, CY1 = 0.0010, 0.0380
    BY1 = 0.2150
    W = 0.0110
    # ---------------- frame (static)
    prof = [(0.0580, -0.0230, 0.004), (0.0560, -0.0350, 0.004), (0.0440, -0.0400, 0.006), (-0.0072, -0.0400), (-0.0072, -0.0322),
            (0.0380, -0.0322), (0.0420, -0.0230, 0.002)]
    g.add(L.extrude("frame", prof, -W, W, k("frame"), bev=0.0006))
    rear = L.fillet([(-0.0040, 0.0100), (-0.0085, 0.0100, 0.003), (-0.0160, 0.0040, 0.006), (-0.0190, -0.0100, 0.005),
                     (-0.0158, -0.0340, 0.005), (-0.0090, -0.0400, 0.003), (-0.0040, -0.0400)])
    fr = L.pillow("frame_rear", rear, lambda y, z: 0.0100 + 0.0010 * np.clip((y + 0.016) / 0.010, 0, 1), k("frame"),
                  round_r=0.0032, step=0.0016)
    L.boolean(fr, [L.box("hslot", -0.0049, 0.0049, -0.0260, -0.0050, -0.0240, 0.0200, "blued", bev=0)])
    L.finish(fr, math.radians(60))
    g.add(fr)
    shield = L.loft("shield", [(-0.0062, 0.0172), (-0.0055, 0.0185), (0.0003, 0.0185)], k("frame"), 64, 0.0, CZ)
    L.boolean(shield, [L.cyl("fph", 0.0011, -0.012, 0.002, "blued", 12)])
    L.bevel(shield, 0.0004, 2, 35)
    L.finish(shield)
    g.add(shield)
    gpath = L.catmull([(0.0270, -0.0398), (0.0262, -0.0470), (0.0210, -0.0570), (0.0115, -0.0640), (0.0005, -0.0652),
                       (-0.0080, -0.0610), (-0.0115, -0.0530), (-0.0115, -0.0450), (-0.0105, -0.0405)], 5)
    g.add(L.sweep("guard", L.path_yz(gpath), L.section_rect(0.0080, 0.0036, 0.0015), k("guard")))
    outline = L.catmull([(-0.0185, -0.0070), (-0.0270, -0.0250), (-0.0370, -0.0460), (-0.0440, -0.0700), (-0.0470, -0.0940),
                         (-0.0450, -0.1080), (-0.0360, -0.1140), (-0.0260, -0.1110), (-0.0215, -0.0980), (-0.0190, -0.0800),
                         (-0.0150, -0.0620), (-0.0110, -0.0490), (-0.0094, -0.0400), (-0.0150, -0.0330)], 5, closed=True)
    g.add(L.pillow("gripframe", outline, 0.0094, k("guard"), round_r=0.0055, step=0.0024))
    panel = L.catmull([(-0.0172, -0.0240), (-0.0258, -0.0290), (-0.0352, -0.0470), (-0.0420, -0.0700), (-0.0448, -0.0930),
                       (-0.0430, -0.1050), (-0.0358, -0.1100), (-0.0272, -0.1075), (-0.0232, -0.0965), (-0.0206, -0.0795),
                       (-0.0166, -0.0615), (-0.0124, -0.0482), (-0.0112, -0.0400), (-0.0150, -0.0345)], 5, closed=True)
    g.add(L.pillow("grip", panel, lambda y, z: 0.0128 + 0.0022 * np.clip(1 - ((z + 0.075) / 0.035) ** 2, 0, 1), k("grip"),
                   round_r=0.0060, step=0.0022))
    g.spec["checker"].append({"kinds": [k("grip")], "normal": (1, 0, 0), "min_dot": 0.5, "center": (-0.0315, -0.0740),
                              "radii": (0.0095, 0.0250), "angle": 72.0, "pitch": 0.0013, "depth": 0.0003, "border": True})
    g.spec["grain"][k("grip")] = (0, 0.3, -1.0)
    for sx, ax in ((0.0151, "x+"), (-0.0151, "x-")):
        g.add(L.screw("gscrew", (sx, -0.0315, -0.0740), ax, 0.0028, k("small"), slot_angle=30))
    for sx, ax in ((W + 0.0001, "x+"), (-W - 0.0001, "x-")):
        g.add(L.screw("hscrew", (sx, -0.0125, -0.0150), ax, 0.0025, k("small"), slot_angle=60 if sx > 0 else 20))
        g.add(L.screw("tscrew", (sx, 0.0090, -0.0370), ax, 0.0021, k("small"), slot_angle=100 if sx > 0 else 45))
        g.add(L.screw("hinge", (sx, 0.0500, -0.0285), ax, 0.0030, k("small"), slot_angle=10 if sx > 0 else 80))
    # ---------------- hammer, trigger
    g.part("hammer", (0, -0.0125, -0.0150), {"type": "rot", "axis": (1, 0, 0), "open": 48.0, "half": 18.0})
    hprof = [(-0.0068, -0.0090, 0.002), (-0.0068, 0.0035, 0.001), (-0.0084, 0.0080, 0.003), (-0.0140, 0.0110, 0.005),
             (-0.0205, 0.0140, 0.005), (-0.0255, 0.0150, 0.003), (-0.0268, 0.0128, 0.003), (-0.0240, 0.0098, 0.004),
             (-0.0200, 0.0040, 0.006), (-0.0188, -0.0120, 0.004), (-0.0125, -0.0215, 0.005), (-0.0078, -0.0180, 0.003)]
    g.add(L.extrude("hammer_b", hprof, -0.0040, 0.0040, k("hammer"), bev=0.0005), "hammer")
    g.spec["checker"].append({"kinds": [k("hammer")], "normal": (0, -0.3, 0.95), "min_dot": 0.45, "center": (-0.0235, 0.0145),
                              "radii": (0.004, 0.006), "angle": 15.0, "pitch": 0.0010, "depth": 0.00025, "border": False,
                              "shape": "box"})
    g.part("trigger", (0, 0.0090, -0.0370), {"type": "rot", "axis": (1, 0, 0), "open": -18.0})
    tprof = [(0.0112, -0.0340), (0.0118, -0.0430, 0.003), (0.0108, -0.0510, 0.006), (0.0080, -0.0580, 0.005),
             (0.0050, -0.0612, 0.0015), (0.0030, -0.0598, 0.0015), (0.0055, -0.0540, 0.006), (0.0072, -0.0450, 0.003),
             (0.0072, -0.0340)]
    g.add(L.extrude("trigger_b", tprof, -0.0028, 0.0028, k("small"), bev=0.0005), "trigger")
    # ---------------- barrel assembly (part, hinged at the front of the frame)
    g.part("barrels", (0, 0.0500, -0.0285), {"type": "rot", "axis": (1, 0, 0), "open": -52.0})
    br = [(0.0440, 0.0080), (0.0480, 0.0084), (BY1 - 0.0012, 0.0076), (BY1, 0.0071), (BY1, 0.0061), (BY1 - 0.0010, 0.0054),
          (BY1 - 0.0012, 0.0052), (BY1 - 0.08, 0.0052)]
    g.add(L.loft("barrel", br, k("barrel"), 48), "barrels")
    g.add(L.extrude_xz("rib", [(-0.0030, 0.0060), (0.0030, 0.0060), (0.0030, 0.0098, 0.0012), (-0.0030, 0.0098, 0.0012)],
                       0.0440, BY1 - 0.004, k("barrel"), bev=0.0003), "barrels")
    fs = [(BY1 - 0.014, 0.0095), (BY1 - 0.002, 0.0095), (BY1 - 0.003, 0.0118, 0.001), (BY1 - 0.008, 0.0135, 0.002),
          (BY1 - 0.012, 0.0115, 0.002)]
    g.add(L.extrude("fsight", fs, -0.0009, 0.0009, k("barrel"), bev=0.0002), "barrels")
    blk = [(0.0388, 0.0125, 0.002), (0.0560, 0.0110, 0.004), (0.0610, 0.0000, 0.006), (0.0600, -0.0180, 0.004),
           (0.0540, -0.0262, 0.004), (0.0440, -0.0262, 0.003), (0.0388, -0.0150)]
    g.add(L.extrude("bblock", blk, -W, W, k("frame"), bev=0.0006), "barrels")
    g.add(L.extrude("blug", [(0.0550, -0.0050), (0.0880, -0.0050, 0.004), (0.0860, -0.0105, 0.003), (0.0550, -0.0180)],
                    -0.0055, 0.0055, k("frame"), bev=0.0005), "barrels")
    sec = [(-0.0075, 0.0076), (0.0075, 0.0076), (0.0075, 0.0105, 0.002), (0.0035, 0.0122, 0.0025), (-0.0035, 0.0122, 0.0025),
           (-0.0075, 0.0105, 0.002)]
    g.add(L.extrude_xz("topstrap", sec, -0.0100, 0.0395, k("frame"), bev=0.0004), "barrels")
    latch = L.extrude("latch", [(-0.0145, 0.0080), (-0.0040, 0.0080), (-0.0040, 0.0140, 0.002), (-0.0080, 0.0192, 0.002),
                                (-0.0145, 0.0186, 0.002)], -0.0080, 0.0080, k("frame"), bev=0.0005)
    L.boolean(latch, [L.box("rn", -0.0012, 0.0012, -0.02, 0.0, 0.0160, 0.03, "blued", bev=0)])
    L.finish(latch)
    g.add(latch, "barrels")
    g.part("cylinder", (0, 0.02, CZ), {"type": "rot", "axis": (0, 1, 0), "open": 60.0, "steps": 6}, parent="barrels")
    revolver_cylinder(g, "cyl", "cylinder", CY0, CY1, CZ, CR, 0.0055, 0.0125, flute_r=0.0038)
    g.part("ejector", (0, 0.0, CZ), {"type": "slide", "axis": (0, -1, 0), "open": 0.008}, parent="cylinder")
    g.add(L.loft("star", [(-0.0004, 0.0140), (0.0008, 0.0145)], k("pin"), 6, 0.0, CZ, phase=0.0), "ejector")
    g.add(L.loft("starpin", [(-0.0010, 0.0026), (0.0012, 0.0026)], k("pin"), 16, 0.0, CZ), "ejector")
    # ---------------- markers
    g.marker("muzzle", (0, BY1, 0))
    g.marker("grip_r", (0, -0.0290, -0.0700))
    g.marker("grip_l", (-0.0130, -0.0250, -0.0880))
    g.marker("sight_rear", (0, -0.0100, 0.0165))
    g.marker("sight_front", (0, BY1 - 0.007, 0.0133))
    g.marker("holster_attach", (0, 0.0200, CZ))
    g.marker("shell_eject", (0, -0.002, CZ), fwd=(0.1, -1.0, 0.8))
    g.spec["handling"] += [((BY1 - 0.05, BY1), (-0.02, 0.02), 0.3), ((-0.03, 0.0), (-0.01, 0.025), 0.4)]
    g.detail_target = (0.004, 0.0, -0.012)


BUILDERS = {"lockhart_sa": build_lockhart, "sheridan_dao": build_sheridan, "talbot_pocket": build_talbot}
