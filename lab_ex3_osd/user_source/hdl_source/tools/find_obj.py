#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
find_obj.py  --  自动定位照片里的"最强色块"并统计特征

不靠手动框坐标：直接按色相/色度找出最像目标的连通区域，
打印该区域的中位颜色 + 面积，用来定阈值。
"""

import sys, os
import numpy as np
from PIL import Image
from collections import deque


def find_blobs(mask, min_area):
    H, W = mask.shape
    seen = np.zeros_like(mask, bool)
    out = []
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not seen[y, x]:
                q = deque([(y, x)])
                seen[y, x] = True
                pix = []
                while q:
                    cy, cx = q.popleft()
                    pix.append((cy, cx))
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = cy + dy, cx + dx
                            if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                                seen[ny, nx] = True
                                q.append((ny, nx))
                if len(pix) >= min_area:
                    ys = [p[0] for p in pix]
                    xs = [p[1] for p in pix]
                    out.append({"n": len(pix),
                                "y0": min(ys), "y1": max(ys),
                                "x0": min(xs), "x1": max(xs),
                                "pix": pix})
    out.sort(key=lambda d: -d["n"])
    return out


def report(path, tag):
    im = Image.open(path).convert("RGB").resize((1280, 720), Image.BILINEAR)
    px = np.asarray(im).astype(np.int16)
    s = px[::8, ::8, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    print("### %s  (%dx%d)" % (tag, im.width, im.height))

    # 找"橙红"：R 主导且 R-B 大
    for name, mask in (
        ("R主导(红/橙)", (r > g) & (r > b) & (np.abs(r - b) >= 60) & (r >= 60)),
        ("黄绿(G主导)", (g >= r) & (g >= b) & (chroma >= 40)),
        ("蓝(B主导)", (b > r) & (b > g) & (chroma >= 40)),
        ("深色", (mx < 70) & (chroma < 40)),
    ):
        blobs = find_blobs(mask, 20)
        print("  [%s] 命中格=%d  连通块=%d" % (name, mask.sum(), len(blobs)))
        for bl in blobs[:4]:
            ys = np.array([p[0] for p in bl["pix"]])
            xs = np.array([p[1] for p in bl["pix"]])
            rr = r[ys, xs]
            gg = g[ys, xs]
            bb = b[ys, xs]
            print("      块 n=%-5d  格范围 x[%3d,%3d] y[%3d,%3d]  "
                  "RGB中位=(%3d,%3d,%3d) chroma中位=%3d  sat比=%.2f"
                  % (bl["n"], bl["x0"], bl["x1"], bl["y0"], bl["y1"],
                     np.median(rr), np.median(gg), np.median(bb),
                     np.median(np.maximum(np.maximum(rr, gg), bb) -
                               np.minimum(np.minimum(rr, gg), bb)),
                     np.median(np.maximum(np.maximum(rr, gg), bb) -
                               np.minimum(np.minimum(rr, gg), bb)) /
                     max(np.median(np.maximum(np.maximum(rr, gg), bb)), 1)))
    print()


if __name__ == "__main__":
    for p in sys.argv[1:]:
        report(p, os.path.basename(p)[:36])
