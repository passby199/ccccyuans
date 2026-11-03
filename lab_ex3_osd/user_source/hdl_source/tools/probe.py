#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
probe.py  --  现场照片取证 + 掩膜可视化

用法:
    python tools/probe.py <photo> [--crop x0 y0 x1 y1 ...] [--out out.png]

功能
---------------------------------------------------------------------------
1. 打印照片原始尺寸
2. 对每个 --crop 矩形（原始像素坐标）统计 RGB / sat / max 分布
3. 用当前判据生成 orange/vivid/dark 掩膜，拼成一张对照图存出来
"""

import sys, os
import numpy as np
from PIL import Image

W, H = 160, 90
DS = 8

ORANGE_TH = 100
ORANGE_RMIN = 60
BLK_TH = 60
VIVID_SAT = 40
BLK_SAT = 32


def masks(px):
    s = px[::DS, ::DS, :].astype(np.int16)
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = mx - mn
    orange = (r > g) & (r > b) & (np.abs(r - b) >= ORANGE_TH) & (r >= ORANGE_RMIN)
    vivid = (sat >= VIVID_SAT) & (((g >= r) & (g >= b)) | ((b >= r) & (b >= g)))
    dark = (mx < BLK_TH) & (sat < BLK_SAT)
    return orange, vivid, dark


def probe_rect(img, name, box):
    x0, y0, x1, y1 = box
    crop = np.asarray(img.crop(box)).reshape(-1, 3).astype(np.int16)
    mx = np.maximum(np.maximum(crop[:, 0], crop[:, 1]), crop[:, 2])
    mn = np.minimum(np.minimum(crop[:, 0], crop[:, 1]), crop[:, 2])
    sat = mx - mn
    print("  [%s] %s n=%d" % (name, box, len(crop)))
    print("      R med=%3d p10=%3d p90=%3d   G med=%3d   B med=%3d   sat med=%3d p90=%3d"
          % (np.median(crop[:, 0]), np.percentile(crop[:, 0], 10), np.percentile(crop[:, 0], 90),
             np.median(crop[:, 1]), np.median(crop[:, 2]),
             np.median(sat), np.percentile(sat, 90)))
    hist = []
    for lo, hi in [(0, 30), (30, 45), (45, 60), (60, 80), (80, 110), (110, 160), (160, 256)]:
        n = int(((mx >= lo) & (mx < hi)).sum())
        hist.append("[%3d,%3d)=%4d %4.1f%%" % (lo, hi, n, 100.0 * n / len(crop)))
    print("      max(RGB) 分档: " + "  ".join(hist))


def overlay(img, out):
    px = np.asarray(img.resize((1280, 720), Image.BILINEAR))
    o, v, d = masks(px)
    panels = []
    base = np.asarray(img.resize((640, 360), Image.BILINEAR)).copy()
    for m, col in ((o, (255, 140, 0)), (v, (0, 255, 0)), (d, (0, 200, 255))):
        p = base.copy()
        mm = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((640, 360), Image.NEAREST))
        sel = mm > 0
        for c in range(3):
            p[:, :, c][sel] = col[c]
        panels.append(p)
    top = np.concatenate([base, panels[0], panels[1]], axis=1)
    bot = np.concatenate([panels[2],
                          np.zeros((360, 640, 3), np.uint8),
                          np.zeros((360, 640, 3), np.uint8)], axis=1)
    out_img = Image.fromarray(np.concatenate([top, bot], axis=0))
    out_img.save(out)
    print("  掩膜图已存: %s" % out)
    print("  命中格数: orange=%d vivid=%d dark=%d" % (o.sum(), v.sum(), d.sum()))


if __name__ == "__main__":
    args = sys.argv[1:]
    photo = args[0]
    crops = []
    out = None
    i = 1
    while i < len(args):
        if args[i] == "--crop":
            n = int(args[i + 1])
            vals = [int(x) for x in args[i + 2:i + 2 + 4 * n]]
            crops = [tuple(vals[k:k + 4]) for k in range(0, len(vals), 4)]
            i += 2 + 4 * n
        elif args[i] == "--out":
            out = args[i + 1]
            i += 2
        else:
            i += 1

    img = Image.open(photo).convert("RGB")
    print("照片: %s  尺寸 %dx%d" % (os.path.basename(photo), img.width, img.height))
    for k, box in enumerate(crops):
        probe_rect(img, "crop%d" % k, box)
    if out:
        overlay(img, out)
