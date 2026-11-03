#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_grid.py -- 网格化颜色统计（raw 域），用于对齐真实目标位置
每张图输出 16x9 网格，每格给 median R,G,B（raw域）与 chroma
"""
import os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v6_model as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out_eval")
GX, GY = 16, 9


def grid(scene):
    p = os.path.join(OUT, "win_%s.png" % scene)
    px = M.load_default(p)
    raw = M.disp_to_raw(px)
    print("=" * 110)
    print("场景: %s   (raw 域, %dx%d 网格)" % (scene, GX, GY))
    print("  每格 medR medG medB | chroma")
    for gy in range(GY):
        row = []
        for gx in range(GX):
            x0 = gx * 1280 // GX; x1 = (gx + 1) * 1280 // GX
            y0 = gy * 720 // GY;  y1 = (gy + 1) * 720 // GY
            a = raw[y0:y1, x0:x1].reshape(-1, 3)
            r = int(np.median(a[:, 0])); g = int(np.median(a[:, 1])); b = int(np.median(a[:, 2]))
            ch = max(r, g, b) - min(r, g, b)
            row.append("%3d,%3d,%3d|%3d" % (r, g, b, ch))
        print(" y%-2d " % gy + "  ".join(row))
    print("      " + "  ".join("c%-13d" % gx for gx in range(GX)))


if __name__ == "__main__":
    for sc in (sys.argv[1:] or ["改锥", "黑色物体"]):
        grid(sc)
