#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
scan_win.py -- 扫描竖拍照片所有可能的 16:9 裁切窗口，输出每个窗口的检测结果

背景
---------------------------------------------------------------------------
竖拍照片 1080x2418 想等效"横屏摄像头视角"，必须裁 16:9。
但裁切位置不同，物体在画面里的位置/大小完全不同。之前用固定
top=0.30 的居中裁切，把黑色方块(位于照片下 1/3)整个裁掉了 —— 于是
"黑色物体"的框落到了键盘区。这是裁切问题，不是判据问题。

本脚本对每张照片枚举所有 top 位置，逐个跑检测并打印，��确认：
  1) 哪个窗口能稳定检出目标
  2) 该窗口下有无误检
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

# ---------- 颜色判据 v5 ----------
ORANGE_RB, ORANGE_RG, ORANGE_RMIN = 60, 45, 140
VIVID_SAT = 60
BLK_TH, BLK_SAT = 40, 24
MIN_PIX, MAX_W, MAX_H, PROJ_TH = 15, 60, 45, 2


def classify(s):
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    orange = ((r >= g) & (r >= b) & ((r - b) >= ORANGE_RB) &
              ((r - g) >= ORANGE_RG) & (r >= ORANGE_RMIN))
    yg = ((g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) &
          (chroma >= VIVID_SAT))
    b_lead = (b > r) & (b >= g) & (chroma >= VIVID_SAT)
    r_lead = (r > g) & (r > b) & (chroma >= VIVID_SAT)
    dark = (mx < BLK_TH) & (chroma < BLK_SAT)
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


def vote_refine(mask, vr=8, vc=10, expand=1, min_pix=MIN_PIX,
                max_w=MAX_W, max_h=MAX_H):
    bh, bw = H // vr, W // vc
    best = None
    for ty in range(vr):
        for tx in range(vc):
            r = row_box(mask, tx * bw, (tx + 1) * bw, ty * bh, (ty + 1) * bh)
            if r is None or r[4] < min_pix:
                continue
            if (r[1] - r[0]) > max_w or (r[3] - r[2]) > max_h:
                continue
            if best is None or r[4] > best[4]:
                best = r + (ty, tx)
    if best is None:
        return None
    _, _, _, _, _, by, bx = best
    y_lo = max(0, (by - expand) * bh); y_hi = min(H, (by + expand + 1) * bh)
    x_lo = max(0, (bx - expand) * bw); x_hi = min(W, (bx + expand + 1) * bw)
    r = row_box(mask, x_lo, x_hi, y_lo, y_hi)
    if r is None:
        return None
    x0, x1, y0, y1, cnt = r
    if cnt < min_pix or (x1 - x0) > max_w or (y1 - y0) > max_h:
        return None
    return {"box": (x0, x1, y0, y1), "hits": cnt}


def crop169_at(im, top):
    w, h = im.size
    th = int(w * 9 / 16)
    if th >= h:
        return im.resize((1280, 720), Image.BILINEAR)
    top = max(0, min(top, h - th))
    return im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR)


def summarize(m):
    """返回每类的 (全图命中数, 分区投票框)"""
    out = {}
    for nm in ("orange", "yg", "b_lead", "r_lead", "dark"):
        out[nm] = (int(m[nm].sum()), vote_refine(m[nm]))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for tag, path in (("改锥", SCREW), ("黑色物体", BLACK), ("魔方", CUBE), ("显示器", MON)):
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        print("\n===== %s  (原图 %dx%d, 16:9窗高=%d) =====" % (tag, w, h, th))
        print("  top%%  | 橙(全/框)      | 黄绿(全/框)     | 蓝(全) 红(全) | 黑(全/框)")
        best_rows = []
        for top in range(0, max(1, h - th + 1), max(1, (h - th) // 12)):
            px = np.asarray(crop169_at(im, top))
            s = px.astype(np.int16)[::DS, ::DS, :]
            r = summarize(classify(s))

            def fmt(k):
                n, v = r[k]
                return "%4d %s" % (n, ("%s" % (v["box"],)) if v else "   -     ")

            print("  %3d%% | %s | %s | %4d %4d | %s" % (
                int(100.0 * top / max(1, h - th)),
                fmt("orange"), fmt("yg"), r["b_lead"][0], r["r_lead"][0], fmt("dark")))
            best_rows.append((top, r))
        # 保存最优窗口（按 目标类 命中最多）
        key = {"改锥": "orange", "黑色物体": "dark", "魔方": "yg", "显示器": "yg"}[tag]
        bt, br = max(best_rows, key=lambda z: z[1][key][0])
        px = np.asarray(crop169_at(im, bt))
        Image.fromarray(px).save(os.path.join(OUT, "win_%s.png" % tag))
        print("  >>> 最优窗口 top=%d (%.0f%%)  %s命中=%d  已存 out_eval/win_%s.png"
              % (bt, 100.0 * bt / max(1, h - th), key, br[key][0], tag))


if __name__ == "__main__":
    main()
