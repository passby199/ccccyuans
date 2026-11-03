#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
diag_bands.py -- 逐行追踪 band 演化，定位漏检/误检根因

用法：对指定 照片+窗口 打印每行主簇、band 归属、以及所有 band 的特征。
"""
import os
import sys
import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90
SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
MON   = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

GAPX, VGAP, PROJ_TH = 4, 3, 2
ORANGE_RB, ORANGE_RG, ORANGE_RMIN = 60, 45, 140
YG_SAT = 60
BLK_TH, BLK_SAT = 40, 24
BLK_CTH, BLK_CSAT = 28, 16


def masks(s):
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    return {
        "orange": ((r >= g) & (r >= b) & ((r - b) >= ORANGE_RB) & ((r - g) >= ORANGE_RG) & (r >= ORANGE_RMIN),
                   (r >= g) & (r >= b) & ((r - b) >= ORANGE_RB) & ((r - g) >= ORANGE_RG) & (r >= ORANGE_RMIN)
                   & ((r - b) >= 80) & ((r - g) >= 55) & (r >= ORANGE_RMIN + 30)),
        "yg": ((g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= YG_SAT),
               (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= 80)),
        "dark": ((mx < BLK_TH) & (chroma < BLK_SAT),
                 (mx < BLK_CTH) & (chroma < BLK_CSAT)),
    }


def row_clusters(row):
    out = []
    x = 0
    n = len(row)
    while x < n:
        if row[x]:
            s = x
            while x < n and row[x]:
                x += 1
            e = x - 1
            if out and s <= out[-1][1] + GAPX:
                out[-1] = (out[-1][0], e, out[-1][2] + e - s + 1)
            else:
                out.append((s, e, e - s + 1))
        else:
            x += 1
    return out


def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "cube"
    tops = sys.argv[2:] if len(sys.argv) > 2 else ["45"]
    paths = {"screw": SCREW, "black": BLACK, "cube": CUBE, "mon": MON}
    for tp in tops:
        path = paths[which]
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        top = int(th * 0 + (h - th) * float(tp) / 100.0)
        px = crop169_at(path, top)
        s = px.astype(np.int16)[::DS, ::DS, :]
        m = masks(s)
        print("\n########## %s  top=%d (%.0f%%) ##########" % (which, top, float(tp)))
        for cls in ("orange", "yg", "dark"):
            halo, core = m[cls]
            print("  ---- %s ----" % cls)
            # 逐行主簇
            bands = []
            active = False
            bx0 = bx1 = by0 = by1 = bhalo = bcore = 0
            last = -99
            for y in range(H):
                cl = row_clusters(halo[y])
                if cl:
                    bc = max(cl, key=lambda t: t[2])
                    blo, bhi, bcnt = bc
                    ccount = int(core[y][blo:bhi + 1].sum())
                else:
                    blo = bhi = bcnt = 0
                    ccount = 0
                act = ""
                if bcnt >= PROJ_TH:
                    if not active:
                        active = True
                        bx0, bx1, by0, by1 = blo, bhi, y, y
                        bhalo, bcore = bcnt, ccount
                        act = "NEW"
                    elif blo <= bx1 + GAPX and bhi + GAPX >= bx0:
                        bx0 = min(bx0, blo); bx1 = max(bx1, bhi); by1 = y
                        bhalo += bcnt; bcore += ccount
                        act = "EXT"
                    else:
                        bands.append((bx0, bx1, by0, by1, bhalo, bcore))
                        act = "SPLIT"
                        bx0, bx1, by0, by1 = blo, bhi, y, y
                        bhalo, bcore = bcnt, ccount
                    last = y
                else:
                    if active and (y - last) > VGAP:
                        bands.append((bx0, bx1, by0, by1, bhalo, bcore))
                        act = "END"
                        active = False
                if cls == "yg" and which == "cube":
                    print("    y=%2d cl=%-28s main=(%3d..%3d,n=%4d,c=%4d) band=(%3d..%3d,y%d..%d h=%d c=%d) %s"
                          % (y, str(cl[:3]), blo, bhi, bcnt, ccount,
                             bx0, bx1, by0, by1, bhalo, bcore, act))
            if active:
                bands.append((bx0, bx1, by0, by1, bhalo, bcore))
            print("    最终 band 列表：")
            for (x0, x1, y0, y1, hh, cc) in bands:
                ww = x1 - x0 + 1
                hh2 = y1 - y0 + 1
                print("      x%d..%d y%d..%d  %dx%d  halo=%d core=%d  solid=%.2f cdens=%.2f"
                      % (x0, x1, y0, y1, ww, hh2, hh, cc, hh / float(ww * hh2),
                         cc / float(ww * hh2)))


if __name__ == "__main__":
    main()
