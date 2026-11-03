#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
sweep.py -- 阈值扫描：用【core 自身包围盒密实度】分离真目标 / 干扰源

核心思想
---------------------------------------------------------------------------
halo（宽松层）负责圈形，core（严格层）负责确认。
真目标：core 像素在 core 自己的包围盒里是【致密实心块】-> core_solid 高。
干扰源（键盘暗缝/桌面阴影/屏幕暗条）：core 像素零散 -> core_solid 低。

本脚本对 4 张照片的所有 16:9 窗口做全量扫描，列出每个 band 的
  core_cnt / core_solid / core_dark
从而选出能同时满足"正样本全过、负样本全不过"的门限。
"""
import os
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

POS = {"screw": ("orange", SCREW), "black": ("dark", BLACK), "cube": ("yg", CUBE)}
NEG = [("mon", MON)]


def masks(s):
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    o_h = (r >= g) & (r >= b) & ((r - b) >= ORANGE_RB) & ((r - g) >= ORANGE_RG) & (r >= ORANGE_RMIN)
    o_c = o_h & ((r - b) >= 80) & ((r - g) >= 55) & (r >= ORANGE_RMIN + 30)
    y_h = (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= YG_SAT)
    y_c = y_h & (chroma >= 80)
    d_h = (mx < BLK_TH) & (chroma < BLK_SAT)
    d_c = (mx < BLK_CTH) & (chroma < BLK_CSAT)
    return {"orange": (o_h, o_c), "yg": (y_h, y_c), "dark": (d_h, d_c)}


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


def bands_of(halo, core):
    """halo 圈 band；band 内额外维护 core 自身的包围盒"""
    res = []
    active = False
    bx0 = bx1 = by0 = by1 = 0
    cx0 = cx1 = cy0 = cy1 = 0
    bhalo = bcore = 0
    last = -99

    def close():
        if not active:
            return
        if bcore > 0:
            cw = cx1 - cx0 + 1
            ch = cy1 - cy0 + 1
            res.append({
                "halo_box": (bx0, bx1, by0, by1),
                "core_box": (cx0, cx1, cy0, cy1),
                "halo": bhalo, "core": bcore,
                "core_solid": bcore / float(cw * ch),
                "core_w": cw, "core_h": ch,
                "halo_solid": bhalo / float((bx1 - bx0 + 1) * (by1 - by0 + 1)),
            })

    for y in range(H):
        cl = row_clusters(halo[y])
        if cl:
            bc = max(cl, key=lambda t: t[2])
            blo, bhi, bcnt = bc
            crow = core[y]
            cs = np.nonzero(crow[blo:bhi + 1])[0]
            if len(cs):
                c_lo = int(cs.min()) + blo
                c_hi = int(cs.max()) + blo
                c_cnt = len(cs)
            else:
                c_lo = c_hi = blo
                c_cnt = 0
        else:
            blo = bhi = bcnt = 0
            c_lo = c_hi = 0
            c_cnt = 0

        if bcnt >= PROJ_TH:
            if not active:
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bhalo, bcore = bcnt, c_cnt
                if c_cnt:
                    cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            elif blo <= bx1 + GAPX and bhi + GAPX >= bx0:
                bx0 = min(bx0, blo); bx1 = max(bx1, bhi); by1 = y
                bhalo += bcnt; bcore += c_cnt
                if c_cnt:
                    cx0 = min(cx0, c_lo); cx1 = max(cx1, c_hi)
                    cy0 = min(cy0, y); cy1 = max(cy1, y)
            else:
                close()
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bhalo, bcore = bcnt, c_cnt
                if c_cnt:
                    cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            last = y
        else:
            if active and (y - last) > VGAP:
                close()
                active = False
    close()
    return res


def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def scan(tag, path, cls):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    span = max(1, h - th)
    out = []
    for top in range(0, span + 1, max(1, span // 20)):
        px = crop169_at(path, top)
        s = px.astype(np.int16)[::DS, ::DS, :]
        m = masks(s)
        halo, core = m[cls]
        for b in bands_of(halo, core):
            if b["core"] < 20:
                continue
            out.append((int(100.0 * top / span), b))
    return out


def main():
    for cls in ("orange", "yg", "dark"):
        print("\n================ 类: %s ================" % cls)
        print("---- 正样本 ----")
        for tag, (c, path) in POS.items():
            if c != cls:
                continue
            rows = scan(tag, path, cls)
            for pct, b in rows:
                print("  %-8s top=%3d%% core=%5d core_solid=%.3f corebox=%dx%d halosolid=%.3f"
                      % (tag, pct, b["core"], b["core_solid"], b["core_w"], b["core_h"],
                         b["halo_solid"]))
        print("---- 负样本(显示器) ----")
        for tag, path in NEG:
            rows = scan(tag, path, cls)
            for pct, b in rows:
                print("  %-8s top=%3d%% core=%5d core_solid=%.3f corebox=%dx%d halosolid=%.3f"
                      % (tag, pct, b["core"], b["core_solid"], b["core_w"], b["core_h"],
                         b["halo_solid"]))


if __name__ == "__main__":
    main()
