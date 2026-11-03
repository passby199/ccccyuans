#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
probe2.py  --  实物区域精确取证（手动框选 + 归一化色度）

要点
---------------------------------------------------------------------------
1. 手机照片经过手机 ISP（自动白平衡 / gamma / HDR），颜色跟 SC500 的 raw 域
   差别很大。所以阈值必须用【相对量】（通道比值、色度差）而不是绝对 RGB。
2. 同时输出：
   - 绝对 RGB 中位数
   - 归一化色度  r=R/max, g=G/max, b=B/max
   - 与"白色/灰色"的偏离度  chroma = max - min
   - 色相角（HSV 风格）
"""

import sys, os, math
import numpy as np
from PIL import Image


def hsv_h(r, g, b):
    mx = max(r, g, b)
    mn = min(r, g, b)
    d = mx - mn
    if d == 0:
        return -1.0
    if mx == r:
        h = 60 * (((g - b) / d) % 6)
    elif mx == g:
        h = 60 * ((b - r) / d + 2)
    else:
        h = 60 * ((r - g) / d + 4)
    return h


def probe(img, name, box):
    x0, y0, x1, y1 = box
    c = np.asarray(img.crop(box)).reshape(-1, 3).astype(np.float64)
    r, g, b = c[:, 0], c[:, 1], c[:, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    s = np.where(mx > 0, chroma / np.maximum(mx, 1), 0)     # HSV 饱和度 0..1
    # 归一化色度
    nr = np.where(mx > 0, r / np.maximum(mx, 1), 0)
    ng = np.where(mx > 0, g / np.maximum(mx, 1), 0)
    nb = np.where(mx > 0, b / np.maximum(mx, 1), 0)
    hues = [hsv_h(int(np.median(r)), int(np.median(g)), int(np.median(b)))]
    # 主导色相直方图
    hh = np.array([hsv_h(int(rr), int(gg), int(bb)) for rr, gg, bb in c])
    hh = hh[hh >= 0]
    bins = np.zeros(12)
    for x in hh:
        bins[int(x // 30) % 12] += 1
    tot = max(len(hh), 1)

    print("  [%s] %s  n=%d" % (name, box, len(c)))
    print("      RGB中位 = (%3d,%3d,%3d)   max=%3d  chroma=%3d  sat=%.2f  hue=%5.1f"
          % (np.median(r), np.median(g), np.median(b),
             np.median(mx), np.median(chroma), np.median(s), hues[0]))
    print("      归一化  r=%.3f g=%.3f b=%.3f   (R-B)/max=%.3f  (G-R)/max=%+.3f"
          % (np.median(nr), np.median(ng), np.median(nb),
             (np.median(nr) - np.median(nb)),
             (np.median(ng) - np.median(nr))))
    top = np.argsort(-bins)[:4]
    print("      色相分布: " + "  ".join(
        "%d-%d度 %4.1f%%" % (int(i * 30), int(i * 30) + 30, 100.0 * bins[i] / tot) for i in top))
    for lo, hi in [(0, 30), (30, 45), (45, 60), (60, 80), (80, 110), (110, 160), (160, 256)]:
        n = int(((mx >= lo) & (mx < hi)).sum())
        if n:
            print("        max[%3d,%3d) %5d %5.1f%%" % (lo, hi, n, 100.0 * n / len(c)))


if __name__ == "__main__":
    args = sys.argv[1:]
    photo = args[0]
    img = Image.open(photo).convert("RGB")
    print("照片 %s  %dx%d" % (os.path.basename(photo), img.width, img.height))
    vals = [int(x) for x in args[1:]]
    for k in range(0, len(vals), 4):
        probe(img, "c%d" % (k // 4), tuple(vals[k:k + 4]))
