#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
exp_v8.py  --  分区投票 + 簇内精修，根治背景污染

思路
---------------------------------------------------------------------------
v4/v5 的根本缺陷：**全局外接框**。背景（键盘阴影、屏幕内容）只要有
零星命中，就会把 min/max 撑到全图，真目标连带被"尺寸上限"否决。

v8 改成两级：
  1) 分区投票：画面切成 R x C 个"投票区"，每区统计该类命中数。
     得分最高的区 = 目标所在区（背景再大也集中在一两个区里）。
  2) 区内精修：只在这个区的 3x3 邻域里做行投影外接框。
     背景的其它区完全不参与，框不会被撑爆。

同时把"魔方"改成【双色相共现】：魔方 = 黄绿核心(yg) 且 邻域里有
蓝/红高饱和块。笔记本屏幕上的 PPT 内容只有单色相，不会成对出现。
"""

import sys
import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90

# ---- 判据参数 ----
ORANGE_RB = 60      # P23
ORANGE_RG = 45      # P28
ORANGE_RMIN = 140   # P27
VIVID_SAT = 60      # P26
BLK_TH = 40         # P25
BLK_SAT = 24
MIN_PIX = 15        # P24
MAX_W = 60          # 宽度上限（格）= 480 像素
MAX_H = 45          # 高度上限（格）= 360 像素
PROJ_TH = 2

# 投票区划分（格）
VR, VC = 6, 8      # 6 行 x 8 列 = 48 个投票区，每区 27x20 格


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


def rowproj_box(mask, x_lo, x_hi, y_lo, y_hi, proj_th=PROJ_TH):
    """在限定窗口内做行投影外接框"""
    x0 = x1 = y0 = y1 = None
    for yy in range(max(y_lo, 0), min(y_hi, H)):
        row = np.nonzero(mask[yy, max(x_lo, 0):min(x_hi, W)])[0]
        if len(row) >= proj_th:
            if y0 is None:
                y0 = yy
            y1 = yy
            a = int(row.min()) + max(x_lo, 0)
            b = int(row.max()) + max(x_lo, 0)
            x0 = a if x0 is None else min(x0, a)
            x1 = b if x1 is None else max(x1, b)
    if y0 is None:
        return None
    return x0, x1, y0, y1, int(mask[max(y_lo, 0):min(y_hi, H), max(x_lo, 0):min(x_hi, W)].sum())


def vote_and_box(mask, vr=VR, vc=VC, win=1, max_w=MAX_W, max_h=MAX_H, min_pix=MIN_PIX):
    """分区投票 -> 取最高分区 -> 3x3 邻域内精修"""
    tiles = np.zeros((vr, vc), int)
    bh, bw = H // vr, W // vc
    for ty in range(vr):
        for tx in range(vc):
            tiles[ty, tx] = mask[ty * bh:(ty + 1) * bh, tx * bw:(tx + 1) * bw].sum()
    best = int(np.argmax(tiles))
    by, bx = divmod(best, vc)
    y_lo = max(0, (by - win) * bh)
    y_hi = min(H, (by + win + 1) * bh)
    x_lo = max(0, (bx - win) * bw)
    x_hi = min(W, (bx + win + 1) * bw)
    bb = rowproj_box(mask, x_lo, x_hi, y_lo, y_hi)
    if bb is None:
        return None
    x0, x1, y0, y1, cnt = bb
    if cnt < min_pix:
        return None
    if (x1 - x0) > max_w or (y1 - y0) > max_h:
        return None
    return x0, x1, y0, y1, cnt, (by, bx), int(tiles[by, bx])


def detect(px, **kw):
    m = classify(px)
    out = {}
    for nm, extra in (("orange", False), ("yg", False), ("dark", False)):
        r = vote_and_box(m[nm], **kw)
        out[nm] = r
    # 魔方：yg 有效 且 邻域里有 blue/red 高饱和块
    if out["yg"]:
        x0, x1, y0, y1 = out["yg"][:4]
        pad = 4
        win = np.zeros_like(m["yg"])
        win[max(0, y0 - pad):y1 + pad + 1, max(0, x0 - pad):x1 + pad + 1] = True
        partner = (m["b_lead"] | m["r_lead"]) & win
        out["cube_partner"] = int(partner.sum())
    else:
        out["cube_partner"] = 0
    return out


def show(tag, px, **kw):
    r = detect(px, **kw)
    parts = []
    for nm in ("orange", "yg", "dark"):
        v = r[nm]
        parts.append("%s:%s" % (nm, "%s n=%d %dx%d" % (v[:4], v[4], v[1] - v[0], v[3] - v[2]) if v else "-"))
    parts.append("cubePartner=%d" % r["cube_partner"])
    print("  %-22s %s" % (tag, " | ".join(parts)))


if __name__ == "__main__":
    SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
    BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
    CUBE = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
    MON = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

    def L(p):
        return np.asarray(Image.open(p).convert("RGB").resize((1280, 720), Image.BILINEAR))

    print("【v8 分区投票 —— 整幅 resize（保持之前的可比性）】")
    show("改锥照片", L(SCREW))
    show("黑色物体照片", L(BLACK))
    show("魔方照片", L(CUBE))
    mo = Image.open(MON).convert("RGB")
    show("笔记本屏幕(误检源)", np.asarray(mo.crop((230, 60, 470, 390)).resize((1280, 720), Image.BILINEAR)))
    show("显示器全图", L(MON))

    print("\n【投票区参数扫描】")
    for vr, vc in ((4, 6), (6, 8), (8, 10), (4, 8)):
        print("  VR=%d VC=%d" % (vr, vc))
        show("   改锥", L(SCREW), vr=vr, vc=vc)
        show("   黑色", L(BLACK), vr=vr, vc=vc)
        show("   魔方", L(CUBE), vr=vr, vc=vc)
        show("   屏幕", np.asarray(mo.crop((230, 60, 470, 390)).resize((1280, 720), Image.BILINEAR)), vr=vr, vc=vc)
