#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
exp_v7.py  --  用"居中裁 16:9"模拟真实横屏视场，验证 v6 判据 + 紧凑性筛选

背景
---------------------------------------------------------------------------
现场照片是手机竖拍（1080x2418）。直接 resize 成 1280x720 会把物体
横向拉伸 3.4 倍，外接框尺寸全部失真，不能代表 FPGA 的真实视场。
这里改成【居中裁切 16:9】再缩放，等价于"横屏相机拍到同样的场景"。

紧凑性筛选（超级块投票）
---------------------------------------------------------------------------
背景（键盘/屏幕/桌面阴影）会连成一大片，把外接框撑爆，
连带把真目标也否决掉。用 64x64 像素的"超级块"投票：
    超级块命中数 >= K  →  算有效块
只有【密集相连的有效块】才参与外接框，弥散的噪点自动被剔除。
"""

import sys
import numpy as np
from PIL import Image
from collections import deque

DS = 8
TS = 8                      # 超级块边长（格）= 64x64 像素
TW, TH = 160 // TS, 90 // TS

ORANGE_RB = 60
ORANGE_RG = 45
ORANGE_RMIN = 140
VIVID_SAT = 60
BLK_TH = 40
BLK_SAT = 24
MIN_PIX = 15
TILE_MIN = 4                # 超级块最少命中格数


def crop16x9(p):
    im = Image.open(p).convert("RGB")
    w, h = im.size
    tw = min(w, int(h * 16 / 9))
    left = (w - tw) // 2
    top = int((h - tw * 9 / 16) * 0.35)      # 略偏上，物体通常在手部高度
    return im.crop((left, top, left + tw, top + int(tw * 9 / 16))).resize((1280, 720), Image.BILINEAR)


def cls(px, orb=ORANGE_RB, org=ORANGE_RG, orm=ORANGE_RMIN,
        vs=VIVID_SAT, bt=BLK_TH, bs=BLK_SAT):
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    orange = (r >= g) & (r >= b) & ((r - g) >= org) & ((r - b) >= orb) & (r >= orm)
    yg = (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= vs)
    dark = (mx < bt) & (chroma < bs)
    return {"orange": orange, "yg": yg, "dark": dark}


def largest_cluster(tiles, tile_min=TILE_MIN):
    """超级块层面找最大 4-邻接连通簇，返回 (x0,x1,y0,y1,块数,总命中格)"""
    ok = tiles >= tile_min
    if not ok.any():
        return None
    seen = np.zeros_like(ok)
    best = None
    for y in range(TH):
        for x in range(TW):
            if ok[y, x] and not seen[y, x]:
                q = deque([(y, x)])
                seen[y, x] = True
                cells = []
                while q:
                    cy, cx = q.popleft()
                    cells.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < TH and 0 <= nx < TW and ok[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
                if best is None or len(cells) > len(best):
                    best = cells
    ys = [p[0] for p in best]
    xs = [p[1] for p in best]
    bb = (int(min(xs)) * TS, int(max(xs)) * TS + TS - 1,
          int(min(ys)) * TS, int(max(ys)) * TS + TS - 1)
    hits = int(sum(tiles[p[0], p[1]] for p in best))
    return bb, len(best), hits


def detect(px, tile_min=TILE_MIN, max_w=90, max_h=60):
    res = {}
    for name, mask in cls(px).items():
        tiles = np.zeros((TH, TW), int)
        for ty in range(TH):
            for tx in range(TW):
                tiles[ty, tx] = mask[ty * TS:(ty + 1) * TS, tx * TS:(tx + 1) * TS].sum()
        r = largest_cluster(tiles, tile_min)
        if r is None:
            res[name] = None
            continue
        bb, nblk, hits = r
        w, h = bb[1] - bb[0], bb[3] - bb[2]
        if w > max_w or h > max_h or hits < MIN_PIX:
            res[name] = None
        else:
            res[name] = (bb, nblk, hits, w, h)
    return res


def show(tag, px, **kw):
    r = detect(px, **kw)
    parts = []
    for nm in ("orange", "yg", "dark"):
        v = r[nm]
        parts.append("%s:%s" % (nm, "box=%s nblk=%d hits=%d %dx%d" % (v[0], v[1], v[2], v[3], v[4]) if v else "-"))
    print("  %-22s %s" % (tag, " | ".join(parts)))


if __name__ == "__main__":
    SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
    BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
    CUBE = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
    MON = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

    print("【居中裁 16:9 后】")
    show("改锥照片", np.asarray(crop16x9(SCREW)))
    show("黑色物体照片", np.asarray(crop16x9(BLACK)))
    show("魔方照片", np.asarray(crop16x9(CUBE)))
    mo = Image.open(MON).convert("RGB")
    show("笔记本屏幕(误检源)", np.asarray(mo.crop((230, 60, 470, 390)).resize((1280, 720), Image.BILINEAR)))
    show("显示器全图", np.asarray(crop16x9(MON)))
