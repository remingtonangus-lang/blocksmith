#!/usr/bin/env python3
"""Frontier horse generator: builds the horse with the quadruped generator (tools/animals/quadruped.py,
species parameters in tools/animals/species/horse.py) -> `horse.glb` + `horse_gaits.json`.

Usage: python3 horse_gen.py [--out DIR] [--quick] [--preview] [--no-anim] [--no-tack] [--strips]
(same as `python3 quadruped.py --species horse ...`)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
if "--species" not in sys.argv:
    sys.argv += ["--species", "horse"]

import quadruped  # noqa: E402

if __name__ == "__main__":
    quadruped.main()
