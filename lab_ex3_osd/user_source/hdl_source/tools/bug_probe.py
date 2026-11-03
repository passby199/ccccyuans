#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
bug_probe.py -- 定位 sweep.py 中 core 包围盒异常的原因
"""
import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90
SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
GAPX = 4


def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


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


def main():
    px = crop169_at(SCREW, 0)
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    o_h = (r >= g) & (r >= b) & ((r - b) >= 60) & ((r - g) >= 45) & (r >= 140)
    o_c = o_h & ((r - b) >= 80) & ((r - g) >= 55) & (r >= 170)

    print("halo 总命中=%d  core 总命中=%d" % (o_h.sum(), o_c.sum()))
    print("\n逐行簇（前 12 行 + 关键行）：")
    for y in list(range(0, 12)) + [30, 36, 40, 50, 60, 70, 80, 88]:
        cl = row_clusters(o_h[y])
        clc = row_clusters(o_c[y])
        print("  y=%2d halo簇=%s" % (y, cl[:4]))
        print("        core簇=%s" % (clc[:4],))

    # core 像素的全局坐标分布
    ys, xs = np.nonzero(o_c)
    print("\ncore 像素 x 分布直方(每10格):")
    hist, _ = np.histogram(xs, bins=np.arange(0, W + 10, 10))
    print("  ", hist)
    print("core 像素 y 分布直方(每10格):")
    hist2, _ = np.histogram(ys, bins=np.arange(0, H + 10, 10))
    print("  ", hist2)


if __name__ == "__main__":
    main()
