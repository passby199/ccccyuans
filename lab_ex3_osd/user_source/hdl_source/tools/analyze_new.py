#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
analyze_new.py  --  现场新照片的颜色取证

目的
---------------------------------------------------------------------------
上一轮用 4 张"摆拍"照片定的阈值，实测在真实场景下失效：
  * 改锥（黑色手柄 + 橙色握把）识别不到 —— 橙色占比太小
  * 黑色物体识别不到 —— 周围键盘/桌面同样是黑的
  * 魔方误检飘框 —— 屏幕上任何偏蓝/偏绿的内容都命中"高饱和"

先把这 3 个实物在照片里的真实像素分布量出来，再定阈值。
"""

import sys, glob, os
import numpy as np
from PIL import Image

W, H = 160, 90
DS = 8


def load(p, size=(1280, 720)):
    im = Image.open(p).convert("RGB")
    return np.asarray(im.resize(size, Image.BILINEAR))


def down(px):
    return px[::DS, ::DS, :].astype(np.int16)


def stats(name, px):
    s = down(px)
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = mx - mn
    print("=== %s  (%dx%d -> %dx%d)" % (name, px.shape[1], px.shape[0], W, H))
    print("  R: min=%3d p5=%3d med=%3d p95=%3d max=%3d"
          % (r.min(), np.percentile(r, 5), np.median(r), np.percentile(r, 95), r.max()))
    print("  G: min=%3d p5=%3d med=%3d p95=%3d max=%3d"
          % (g.min(), np.percentile(g, 5), np.median(g), np.percentile(g, 95), g.max()))
    print("  B: min=%3d p5=%3d med=%3d p95=%3d max=%3d"
          % (b.min(), np.percentile(b, 5), np.median(b), np.percentile(b, 95), b.max()))
    print("  sat: med=%3d p90=%3d max=%3d" % (np.median(sat), np.percentile(sat, 90), sat.max()))

    # 当前三分类判据下的格子数
    orange = (r > g) & (r > b) & (np.abs(r - b) >= 100) & (r >= 60)
    vivid = (sat >= 40) & (((g >= r) & (g >= b)) | ((b >= r) & (b >= g)))
    dark = (mx < 60) & (sat < 32)
    print("  当前判据命中格数: orange=%d  vivid=%d  dark=%d"
          % (orange.sum(), vivid.sum(), dark.sum()))

    # 颜色直方图（量化到 16 级）
    q = (s // 16).astype(np.int32)
    key = q[:, :, 0] * 256 + q[:, :, 1] * 16 + q[:, :, 2]
    vals, cnts = np.unique(key, return_counts=True)
    order = np.argsort(-cnts)[:12]
    print("  主要颜色 (R,G,B 中心值, 格数):")
    for i in order:
        k = int(vals[i])
        qr, qg, qb = k // 256, (k // 16) % 16, k % 16
        c = int(cnts[i])
        if c < 3:
            continue
        print("    (%3d,%3d,%3d)  x%-6d  %5.1f%%"
              % (qr * 16 + 8, qg * 16 + 8, qb * 16 + 8, c, 100.0 * c / (W * H)))
    return s


def color_probe(name, px, box):
    """box = (x0,y0,x1,y1) 像素坐标，探查该区域的颜色分布"""
    x0, y0, x1, y1 = box
    crop = px[y0:y1, x0:x1].reshape(-1, 3).astype(np.int16)
    mx = np.maximum(np.maximum(crop[:, 0], crop[:, 1]), crop[:, 2])
    mn = np.minimum(np.minimum(crop[:, 0], crop[:, 1]), crop[:, 2])
    sat = mx - mn
    print("  [%s] 区域 %s  n=%d" % (name, box, len(crop)))
    print("      R med=%3d  G med=%3d  B med=%3d  sat med=%3d"
          % (np.median(crop[:, 0]), np.median(crop[:, 1]),
             np.median(crop[:, 2]), np.median(sat)))
    print("      R p10=%3d p90=%3d   sat p10=%3d p90=%3d"
          % (np.percentile(crop[:, 0], 10), np.percentile(crop[:, 1 + 0], 90),
             np.percentile(sat, 10), np.percentile(sat, 90)))
    # 该区域里 max(R,G,B) 的分布
    for lo, hi in [(0, 40), (40, 60), (60, 80), (80, 120), (120, 200), (200, 256)]:
        n = int(((mx >= lo) & (mx < hi)).sum())
        print("      max in [%3d,%3d): %5d (%5.1f%%)" % (lo, hi, n, 100.0 * n / len(crop)))


if __name__ == "__main__":
    files = sys.argv[1:]
    for f in files:
        px = load(f)
        stats(os.path.basename(f)[:40], px)
        print()
