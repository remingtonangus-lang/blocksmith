"""Blender-as-a-module environment for the Frontier character pipeline.

Locates the source data (MPFB2 checkout, MakeHuman system assets, extra face targets, CMU BVH) and enables MPFB2 as a
Blender extension inside the `bpy` module so its services (HumanService, TargetService, ...) can be used headless.

Source locations come from environment variables (set by tools/characters/fetch_sources.sh) with local fallbacks:
  FRONTIER_MPFB        MPFB2 checkout root           (contains src/mpfb)
  FRONTIER_MH_ASSETS   makehuman_system_assets root  (contains skins/, clothes/, hair/, eyes/, ...)
  FRONTIER_MH_EXTRA    makehumancommunity/extra-targets root (assets/faceunits01, assets/visemes02)
  FRONTIER_CMU         CMU BVH root                  (contains data/NNN/NN_NN.bvh)
"""
import os
import sys
import importlib

HERE = os.path.dirname(os.path.abspath(__file__))
FRONTIER = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC_ROOT = os.environ.get("FRONTIER_CHAR_SRC", os.path.join(FRONTIER, "build", "charsrc"))


def _pick(env, *cands):
    v = os.environ.get(env)
    if v:
        return v
    for c in cands:
        if c and os.path.isdir(c):
            return c
    return cands[0]


MPFB = _pick("FRONTIER_MPFB", os.path.join(SRC_ROOT, "mpfb2"), "/home/user/makehumancommunity/mpfb2")
MH_ASSETS = _pick("FRONTIER_MH_ASSETS", os.path.join(SRC_ROOT, "system_assets"), "/home/user/mhmirrors/system_assets")
MH_EXTRA = _pick("FRONTIER_MH_EXTRA", os.path.join(SRC_ROOT, "extra-targets"), "/home/user/makehumancommunity/extra-targets")
CMU = _pick("FRONTIER_CMU", os.path.join(SRC_ROOT, "cmu-mocap"), "/home/user/mocap/cmu-mocap")
MPFB_DATA = os.path.join(MPFB, "src", "mpfb", "data")

_PKG = "bl_ext.user_default.mpfb"
_enabled = False


def enable_mpfb():
    """Install (symlink) MPFB2 into Blender's user extension repo and enable it. Idempotent."""
    global _enabled
    if _enabled:
        return
    import bpy
    import addon_utils
    ext = bpy.utils.user_resource('EXTENSIONS', path="user_default", create=True)
    link = os.path.join(ext, "mpfb")
    src = os.path.join(MPFB, "src", "mpfb")
    if os.path.islink(link) and os.readlink(link) != src:
        os.unlink(link)
    if not os.path.exists(link):
        os.symlink(src, link)
    addon_utils.enable(_PKG, default_set=True)
    _enabled = True


def svc(name):
    """svc('humanservice').HumanService etc."""
    enable_mpfb()
    return importlib.import_module(_PKG + ".services." + name)


def mpfb_module(path):
    enable_mpfb()
    return importlib.import_module(_PKG + "." + path)


def check_sources():
    missing = []
    for label, p, probe in (("MPFB2", MPFB, "src/mpfb/data/3dobjs/base.obj"),
                            ("MakeHuman system assets", MH_ASSETS, "skins"),
                            ("extra-targets", MH_EXTRA, "assets/faceunits01"),
                            ("CMU BVH", CMU, "data")):
        if not os.path.exists(os.path.join(p, probe)):
            missing.append("%s (%s)" % (label, os.path.join(p, probe)))
    return missing
