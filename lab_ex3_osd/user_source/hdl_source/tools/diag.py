#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
diag.py  --  诊断为什么"检出掩膜但框被否决"

输出每个类的：
  - 命中格总数
  - 按"超级块"(8x8格=64x64像素)投票后的有效块分布
  - 全图外接框 vs 有效块外接框
"""
import sys
import numpy as np
from PIL import Image

DS = 8
TS = 8          # 超级块边长（格）→ 8x8格 = 64x64 像素
TW, TH = 160 // TS, 90 // TS   # 20 x 12 = 240 个超级块


def load(p, size=(1280, 720)):
    return np.asarray(Image.open(p).convert("RGB").resize(size, Image.BILINEAR)).astype(np.int16)


def cls(px, orb=60, org=45, orm=140, vs=60, bt=40, bs=24):
    s = px[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    orange = (r >= g) & (r >= b) & ((r - g) >= org) & ((r - b) >= orb) & (r >= orm)
    yg = (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= vs)
    dark = (mx < bt) & (chroma < bs)
    return {"orange": orange, "yg": yg, "dark": dark}


def raw_bbox(mask, proj_th=2):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None, 0
    x0 = x1 = y0 = y1 = None
    for yy in range(mask.shape[0]):
        row = np.nonzero(mask[yy])[0]
        if len(row) >= proj_th:
            if y0 is None:
                y0 = yy
            y1 = yy
            x0 = int(row.min()) if x0 is None else min(x0, int(row.min()))
            x1 = int(row.max()) if x1 is None else max(x1, int(row.max()))
    if y0 is None:
        return None, int(mask.sum())
    return (x0, x1, y0, y1), int(mask.sum())


def tile_bbox(mask, tile_min=4):
    """超级块投票：只有命中 >= tile_min 格的超级块才参与外接框"""
    tiles = np.zeros((TH, TW), int)
    for ty in range(TH):
        for tx in range(TW):
            tiles[ty, tx] = mask[ty * TS:(ty + 1) * TS, tx * TS:(tx + 1) * TS].sum()
    ok = tiles >= tile_min
    if not ok.any():
        return None, int(mask.sum()), tiles, ok
    ys, xs = np.nonzero(ok)
    bb = (int(xs.min()) * TS, int(xs.max()) * TS + TS - 1,
          int(ys.min()) * TS, int(ys.max()) * TS + TS - 1)
    return bb, int(mask.sum()), tiles, ok


def diag(px, tag):
    print("=== %s" % tag)
    m = cls(px)
    for name, mask in m.items():
        raw, cnt = raw_bbox(mask)
        tb, cnt2, tiles, ok = tile_bbox(mask)
        print("  [%s] 命中格=%d" % (name, cnt))
        print("      全图外接框 = %s   尺寸=%s" %
              (raw, ("%dx%d" % (raw[1] - raw[0], raw[3] - raw[2])) if raw else "-"))
        print("      票选外接框 = %s   尺寸=%s   有效块=%d/%d" %
              (tb, ("%dx%d" % (tb[1] - tb[0], tb[3] - tb[2])) if tb else "-",
               int(ok.sum()), TW * TH))
        if ok.any():
            ys, xs = np.nonzero(ok)
            print("      票选块分布: x[%d..%d] y[%d..%d] (块坐标)" %
                  (xs.min(), xs.max(), ys.min(), ys.max()))
    print()


if __name__ == "__main__":
    SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
    BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
    CUBE = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
    MON = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

    diag(load(SCREW), "改锥照片")
    diag(load(BLACK), "黑色物体照片")
    diag(load(CUBE), "魔方照片")
    mo = Image.open(MON).convert("RGB")
    diag(np.asarray(mo.crop((230, 60, 470, 390)).resize((1280, 720), Image.BILINEAR)), "笔记本屏幕(误检源)")
