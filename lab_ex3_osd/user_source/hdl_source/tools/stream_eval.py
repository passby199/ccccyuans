#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
stream_eval.py -- v5 流式检测算法的精确仿真 + 全窗口回归

算法（逐行流式，无整帧缓存，可在 RTL 里 1:1 实现）
---------------------------------------------------------------------------
行内 1D 聚类（gap 合并）
    扫描一行，遇到命中像素：
      - 若与当前簇的右端 gap <= GAPX，则并入当前簇
      - 否则当前簇结束，与"本行最大簇"比较，然后开新簇
    行末得到该行的【主簇】(lo, hi, cnt)。
    => 远处孤立噪点不会把这一行的横向范围撑开（v4 的主要缺陷）

行带合并（band）
    主簇 cnt >= PROJ_TH 的行视为有效行。
      - 与当前 band 的横向范围有交叠/邻接(GAPY) -> 并入 band
      - 否则结束当前 band，以本行开新 band
    band 结束时算 w/h/密度(dens = cnt/(w*h))，过门限则参与候选。

候选选择
    每类保留 dens 过门限、尺寸合法的 band 中 cnt 最大者。
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

# ---------------- 颜色判据 ----------------
ORANGE_RB, ORANGE_RG, ORANGE_RMIN = 60, 45, 140
YG_SAT = 60
BLK_TH, BLK_SAT = 40, 24

# ---------------- 几何参数 ----------------
GAPX, GAPY = 4, 4
PROJ_TH = 2
MIN_PIX = 40
MIN_DENS = 0.40

# 每类尺寸上限（格）
LIM = {
    "orange": dict(max_w=70, max_h=70, min_pix=60,  min_dens=0.40),
    "yg":     dict(max_w=150, max_h=88, min_pix=200, min_dens=0.35),
    "dark":   dict(max_w=100, max_h=80, min_pix=200, min_dens=0.40),
}


def classify(s):
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    orange = ((r >= g) & (r >= b) & ((r - b) >= ORANGE_RB) &
              ((r - g) >= ORANGE_RG) & (r >= ORANGE_RMIN))
    yg = ((g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) &
          (chroma >= YG_SAT))
    dark = (mx < BLK_TH) & (chroma < BLK_SAT)
    return {"orange": orange, "yg": yg, "dark": dark}


def detect_class(mask, lim):
    """流式仿真：行内 1D 聚类 -> 行带合并 -> 最佳 band"""
    best = None            # (cnt, x0, x1, y0, y1, dens)
    b_active = False
    b_lo = b_hi = 0
    b_y0 = b_y1 = 0
    b_cnt = 0

    for y in range(H):
        row = mask[y]
        # ---- 行内 1D 聚类 ----
        cur_lo = cur_hi = -1
        cur_cnt = 0
        best_lo = best_hi = -1
        best_cnt = 0
        x = 0
        while x < W:
            if row[x]:
                s = x
                while x < W and row[x]:
                    x += 1
                e = x - 1
                if cur_cnt == 0:
                    cur_lo, cur_hi, cur_cnt = s, e, e - s + 1
                elif s <= cur_hi + GAPX:
                    cur_hi = e
                    cur_cnt += e - s + 1
                else:
                    if cur_cnt > best_cnt:
                        best_lo, best_hi, best_cnt = cur_lo, cur_hi, cur_cnt
                    cur_lo, cur_hi, cur_cnt = s, e, e - s + 1
            else:
                x += 1
        if cur_cnt > best_cnt:
            best_lo, best_hi, best_cnt = cur_lo, cur_hi, cur_cnt

        ok = best_cnt >= PROJ_TH

        # ---- 行带合并 ----
        if ok:
            if not b_active:
                b_active = True
                b_lo, b_hi = best_lo, best_hi
                b_y0 = b_y1 = y
                b_cnt = best_cnt
            elif best_lo <= b_hi + GAPY and best_hi + GAPY >= b_lo:
                b_lo = min(b_lo, best_lo)
                b_hi = max(b_hi, best_hi)
                b_y1 = y
                b_cnt += best_cnt
            else:
                # 结束当前 band
                cand = _close(b_lo, b_hi, b_y0, b_y1, b_cnt, lim)
                if cand and (best is None or cand[0] > best[0]):
                    best = cand
                b_active = True
                b_lo, b_hi = best_lo, best_hi
                b_y0 = b_y1 = y
                b_cnt = best_cnt
        else:
            if b_active:
                cand = _close(b_lo, b_hi, b_y0, b_y1, b_cnt, lim)
                if cand and (best is None or cand[0] > best[0]):
                    best = cand
                b_active = False

    if b_active:
        cand = _close(b_lo, b_hi, b_y0, b_y1, b_cnt, lim)
        if cand and (best is None or cand[0] > best[0]):
            best = cand

    if best is None:
        return None
    cnt, x0, x1, y0, y1, dens = best
    return {"box": (x0, x1, y0, y1), "cnt": cnt, "dens": dens,
            "w": x1 - x0 + 1, "h": y1 - y0 + 1}


def _close(x0, x1, y0, y1, cnt, lim):
    w = x1 - x0 + 1
    h = y1 - y0 + 1
    if w > lim["max_w"] or h > lim["max_h"]:
        return None
    if cnt < lim["min_pix"]:
        return None
    dens = cnt / float(w * h)
    if dens < lim["min_dens"]:
        return None
    return (cnt, x0, x1, y0, y1, dens)


def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def detect(px):
    s = px.astype(np.int16)[::DS, ::DS, :]
    m = classify(s)
    return {k: detect_class(m[k], LIM[k]) for k in ("orange", "yg", "dark")}


def fmt(v):
    if not v:
        return "-"
    return "x%d..%d,y%d..%d n=%d d=%.2f" % (v["box"][0], v["box"][1],
                                              v["box"][2], v["box"][3],
                                              v["cnt"], v["dens"])


def main():
    cases = [("改锥(正)", SCREW, "orange"), ("黑色物体(正)", BLACK, "dark"),
             ("魔方(正)", CUBE, "yg"), ("显示器(负)", MON, None)]
    for tag, path, want in cases:
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        span = max(1, h - th)
        print("\n===== %s  (%dx%d) =====" % (tag, w, h))
        print("  top_pct | %-30s | %-30s | %-30s" % ("orange", "yg", "dark"))
        step = max(1, span // 14)
        for top in range(0, span + 1, step):
            r = detect(crop169_at(path, top))
            mark = ""
            if want:
                mark = " <== 命中" if r[want] else ""
            else:
                if any(r.values()):
                    mark = " <== 误检!"
            print("  %3d%%  | %-30s | %-30s | %-30s%s" % (
                int(100.0 * top / span), fmt(r["orange"]), fmt(r["yg"]),
                fmt(r["dark"]), mark))

if __name__ == "__main__":
    main()
