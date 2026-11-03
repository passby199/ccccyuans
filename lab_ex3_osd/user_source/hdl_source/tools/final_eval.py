#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
final_eval.py -- v5 最终算法评估（halo + core 双阈值流式连通域）

判别原理
---------------------------------------------------------------------------
单阈值不够：黑方块 RGB(24,26,23) 与键盘阴影 RGB(~40,42,38) 亮度接近；
橙色握把与屏幕上的红缆亮度接近。
=> 每类用两个阈值：
     halo（宽松）：负责"把区域圈出来"（行内聚类 / band 合并 / 出框）
     core（严格）：负责"确认这是真目标"（band 内 core 像素计数做评分）
真目标 core 占比高、core 绝对数大；干扰源 core 少。

算法严格 RTL 可实现（逐行流式，无整帧缓存）：
  行内 1D 聚类(gap=GAPX) -> 取本行主簇
  主簇与 band 横向交叠 -> 并入 band；否则收尾旧 band
  空行容忍 VGAP 行不断 band
  band 收尾：core_cnt>=min_core 且 core 密度>=min_dens -> 参与候选
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

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")

GAPX, VGAP, PROJ_TH = 4, 3, 2

# ---- 颜色门限（可串口调）----
ORANGE_RB, ORANGE_RG, ORANGE_RMIN = 60, 45, 140
ORANGE_CR, ORANGE_CG = 80, 55      # core: 更严
YG_SAT = 60
YG_CSAT = 80                        # core: 更高饱和
BLK_TH, BLK_SAT = 40, 24
BLK_CTH, BLK_CSAT = 28, 16          # core: 更暗

# ---- 几何门限 ----
CFG = {
    "orange": dict(min_core=30, min_cdens=0.35, max_w=80, max_h=80),
    "yg":     dict(min_core=120, min_cdens=0.35, max_w=150, max_h=88),
    "dark":   dict(min_core=60, min_cdens=0.30, max_w=110, max_h=80),
}


def masks(s):
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    o_h = (r >= g) & (r >= b) & ((r - b) >= ORANGE_RB) & ((r - g) >= ORANGE_RG) & (r >= ORANGE_RMIN)
    o_c = o_h & ((r - b) >= ORANGE_CR) & ((r - g) >= ORANGE_CG) & (r >= ORANGE_RMIN + 30)
    y_h = (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= YG_SAT)
    y_c = y_h & (chroma >= YG_CSAT)
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


def detect_class(halo, core, cfg):
    """流式：halo 圈形，core 评分"""
    best = None
    active = False
    bx0 = bx1 = by0 = by1 = 0
    bhalo = bcore = 0
    last = -99

    for y in range(H):
        cl = row_clusters(halo[y])
        core_row = core[y]
        # 本行主簇（halo 计数最大）
        if cl:
            bc = max(cl, key=lambda t: t[2])
            blo, bhi, bcnt = bc
            # 该簇范围内的 core 计数
            ccount = int(core_row[blo:bhi + 1].sum())
        else:
            blo = bhi = bcnt = 0
            ccount = 0

        if bcnt >= PROJ_TH:
            if not active:
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bhalo, bcore = bcnt, ccount
            elif blo <= bx1 + GAPX and bhi + GAPX >= bx0:
                bx0 = min(bx0, blo); bx1 = max(bx1, bhi); by1 = y
                bhalo += bcnt; bcore += ccount
            else:
                cand = _close(bx0, bx1, by0, by1, bhalo, bcore, cfg)
                if cand and (best is None or cand["core"] > best["core"]):
                    best = cand
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bhalo, bcore = bcnt, ccount
            last = y
        else:
            if active and (y - last) > VGAP:
                cand = _close(bx0, bx1, by0, by1, bhalo, bcore, cfg)
                if cand and (best is None or cand["core"] > best["core"]):
                    best = cand
                active = False

    if active:
        cand = _close(bx0, bx1, by0, by1, bhalo, bcore, cfg)
        if cand and (best is None or cand["core"] > best["core"]):
            best = cand
    return best


def _close(x0, x1, y0, y1, halo, core, cfg):
    w = x1 - x0 + 1
    h = y1 - y0 + 1
    if w > cfg["max_w"] or h > cfg["max_h"]:
        return None
    if core < cfg["min_core"]:
        return None
    cd = core / float(w * h)
    if cd < cfg["min_cdens"]:
        return None
    return {"box": (x0, x1, y0, y1), "core": core, "halo": halo,
            "w": w, "h": h, "cdens": cd}


def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def detect(px):
    s = px.astype(np.int16)[::DS, ::DS, :]
    m = masks(s)
    return {k: detect_class(m[k][0], m[k][1], CFG[k]) for k in ("orange", "yg", "dark")}


def fmt(v):
    if not v:
        return "-"
    return "x%d..%d,y%d..%d c=%d h=%d cd=%.2f" % (
        v["box"][0], v["box"][1], v["box"][2], v["box"][3], v["core"], v["halo"], v["cdens"])


def main():
    cases = [("改锥(正)", SCREW, "orange"), ("黑色物体(正)", BLACK, "dark"),
             ("魔方(正)", CUBE, "yg"), ("显示器(负)", MON, None)]
    for tag, path, want in cases:
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        span = max(1, h - th)
        print("\n===== %s (%dx%d) =====" % (tag, w, h))
        print("  top_pct | %-32s | %-32s | %-32s" % ("orange", "yg", "dark"))
        for top in range(0, span + 1, max(1, span // 12)):
            r = detect(crop169_at(path, top))
            mark = ""
            if want:
                mark = "  <== HIT" if r[want] else ""
            else:
                if any(r.values()):
                    mark = "  <== FALSE-POSITIVE"
            print("  %3d%%    | %-32s | %-32s | %-32s%s" % (
                int(100.0 * top / span), fmt(r["orange"]), fmt(r["yg"]),
                fmt(r["dark"]), mark))


if __name__ == "__main__":
    main()
