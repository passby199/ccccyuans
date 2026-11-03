#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
exp_v10.py  --  细分区投票 + 逐分区打分

v8 的问题：分区太大(27x20格)，黑方块和键盘阴影落在同一个区里，
          框被阴影撑到 56x34 被尺寸上限否决。

v10：把画面切成更细的分区(默认 12x16)，每个区独立做行投影，
     再按"命中密度"选最优区。背景再大也集中在几个区里，
     真目标所在的区密度最高。
"""

import sys
import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90

ORANGE_RB = 60
ORANGE_RG = 45
ORANGE_RMIN = 140
VIVID_SAT = 60
BLK_TH = 40
BLK_SAT = 24
MIN_PIX = 15
MAX_W = 60
MAX_H = 45
PROJ_TH = 2


def classify(px, orb=ORANGE_RB, org=ORANGE_RG, orm=ORANGE_RMIN,
             vs=VIVID_SAT, bt=BLK_TH, bs=BLK_SAT):
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    orange = (r >= g) & (r >= b) & ((r - g) >= org) & ((r - b) >= orb) & (r >= orm)
    yg = (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= vs)
    b_lead = (b > r) & (b >= g) & (chroma >= vs)
    r_lead = (r > g) & (r > b) & (chroma >= vs)
    dark = (mx < bt) & (chroma < bs)
    return {"orange": orange, "yg": yg, "b_lead": b_lead, "r_lead": r_lead, "dark": dark}


def row_box(mask, x_lo, x_hi, y_lo, y_hi):
    x0 = x1 = y0 = y1 = None
    for yy in range(max(y_lo, 0), min(y_hi, H)):
        row = np.nonzero(mask[yy, max(x_lo, 0):min(x_hi, W)])[0]
        if len(row) >= PROJ_TH:
            if y0 is None:
                y0 = yy
            y1 = yy
            a = int(row.min()) + max(x_lo, 0)
            b = int(row.max()) + max(x_lo, 0)
            x0 = a if x0 is None else min(x0, a)
            x1 = b if x1 is None else max(x1, b)
    if y0 is None:
        return None
    cnt = int(mask[max(y_lo, 0):min(y_hi, H), max(x_lo, 0):min(x_hi, W)].sum())
    return x0, x1, y0, y1, cnt


def best_region(mask, vr=12, vc=16, min_pix=MIN_PIX, max_w=MAX_W, max_h=MAX_H):
    """细分区投票：每个分区独立精修，选【命中格数最多】的合法框

    ⚠ 选"命中最多"而不是"密度最高"：
      密度最高会选中一个只有几格的小碎块（fill=1.00 但 hits=48），
      框会小得只框住物体一角。命中数多才代表"这是那个物体"。
      尺寸上限（max_w/max_h）负责挡掉背景大块。
    """
    bh = H // vr
    bw = W // vc
    best = None
    for ty in range(vr):
        for tx in range(vc):
            y_lo, y_hi = ty * bh, (ty + 1) * bh
            x_lo, x_hi = tx * bw, (tx + 1) * bw
            r = row_box(mask, x_lo, x_hi, y_lo, y_hi)
            if r is None:
                continue
            x0, x1, y0, y1, cnt = r
            if cnt < min_pix:
                continue
            w, h = x1 - x0 + 1, y1 - y0 + 1
            if w > max_w or h > max_h:
                continue
            fill = cnt / float(w * h)
            if best is None or cnt > best[0]:
                best = (cnt, (x0, x1, y0, y1), cnt, fill, w, h, (ty, tx))
    if best is None:
        return None
    return {"box": best[1], "hits": best[2], "fill": best[3], "wh": (best[4], best[5]),
            "reg": best[6]}


def detect(px, vr=12, vc=16, **kw):
    m = classify(px)
    out = {}
    for nm in ("orange", "yg", "dark"):
        out[nm] = best_region(m[nm], vr=vr, vc=vc, **kw)
    if out["yg"]:
        x0, x1, y0, y1 = out["yg"]["box"]
        pad = 5
        win = np.zeros_like(m["yg"])
        win[max(0, y0 - pad):y1 + pad + 1, max(0, x0 - pad):x1 + pad + 1] = True
        out["partner"] = int(((m["b_lead"] | m["r_lead"]) & win).sum())
    else:
        out["partner"] = 0
    return out


def show(tag, px, **kw):
    r = detect(px, **kw)
    parts = []
    for nm in ("orange", "yg", "dark"):
        v = r[nm]
        parts.append("%s:%s" % (nm, "%s n=%d fill=%.2f %dx%d" % (v["box"], v["hits"], v["fill"], v["wh"][0], v["wh"][1]) if v else "-"))
    parts.append("P=%d" % r["partner"])
    print("  %-20s %s" % (tag, " | ".join(parts)))


if __name__ == "__main__":
    SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
    BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
    CUBE = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
    MON = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

    def L(p):
        return np.asarray(Image.open(p).convert("RGB").resize((1280, 720), Image.BILINEAR))

    mo = Image.open(MON).convert("RGB")
    scr = np.asarray(mo.crop((230, 60, 470, 390)).resize((1280, 720), Image.BILINEAR))

    for vr, vc in ((12, 16), (9, 12), (8, 10), (15, 20)):
        print("【分区 %dx%d】" % (vr, vc))
        show("改锥照片", L(SCREW), vr=vr, vc=vc)
        show("黑色物体照片", L(BLACK), vr=vr, vc=vc)
        show("魔方照片", L(CUBE), vr=vr, vc=vc)
        show("笔记本屏幕(误检)", scr, vr=vr, vc=vc)
        print()
