#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
stream_cc.py -- v5 最终算法：流式连通域 + 判别特征量化

算法（严格 RTL 可实现：逐行扫描，无整帧缓存）
---------------------------------------------------------------------------
1) 行内聚类：命中像素按 GAPX 合并成簇；本行保留【与当前 band 有交叠】的簇，
   或（band 未激活时）最大的簇。
2) band 合并：与 band 横向有交叠/邻接的簇并入 band；
   连续 VGAP 行没有任何簇接触 band 才结束 band（容忍中间噪声行）。
3) band 收尾：算 w/h/dens/暗度等特征，过门限则参与候选。
4) 每类取特征最优的 band 作为该类检测结果。

同时输出每个 band 的特征，用于分析"真目标 vs 误检"的区分度。
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

ORANGE_RB, ORANGE_RG, ORANGE_RMIN = 60, 45, 140
YG_SAT = 60
BLK_TH, BLK_SAT = 40, 24

GAPX, VGAP = 4, 3
PROJ_TH = 2


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


def row_clusters(row):
    """行内 1D 聚类（gap 合并），返回 [(lo,hi,cnt), ...]"""
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


def stream_bands(mask, s=None):
    """流式连通域：返回所有 band 的特征列表"""
    bands = []
    active = False
    bx0 = bx1 = 0
    by0 = by1 = 0
    bcnt = 0
    last_row = -99

    for y in range(H):
        cl = row_clusters(mask[y])
        touched = False
        for (lo, hi, c) in cl:
            if not active:
                # 取本行最大簇开新 band
                best = max(cl, key=lambda t: t[2])
                bx0, bx1, bcnt = best[0], best[1], best[2]
                by0 = by1 = y
                last_row = y
                active = True
                touched = True
                break
            if lo <= bx1 + GAPX and hi + GAPX >= bx0:
                bx0 = min(bx0, lo)
                bx1 = max(bx1, hi)
                bcnt += c
                touched = True
        if touched:
            by1 = y
            last_row = y
        else:
            if active and (y - last_row) > VGAP:
                bands.append(_feat(bx0, bx1, by0, by1, bcnt, mask, s))
                active = False
    if active:
        bands.append(_feat(bx0, bx1, by0, by1, bcnt, mask, s))
    return bands


def _feat(x0, x1, y0, y1, cnt, mask, s):
    w = x1 - x0 + 1
    h = y1 - y0 + 1
    d = {"box": (x0, x1, y0, y1), "cnt": cnt, "w": w, "h": h,
         "dens": cnt / float(w * h)}
    if s is not None:
        sub = mask[y0:y1 + 1, x0:x1 + 1]
        pix = s[y0:y1 + 1, x0:x1 + 1][sub]
        if len(pix):
            mx = pix.max(axis=1)
            mn = pix.min(axis=1)
            ch = mx - mn
            d["mx_mean"] = float(mx.mean())
            d["mx_p95"] = float(np.percentile(mx, 95))
            d["ch_mean"] = float(ch.mean())
            d["ch_p95"] = float(np.percentile(ch, 95))
            d["bright_ratio"] = float((mx < 24).mean())
    return d


def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def main():
    for tag, path in (("改锥", SCREW), ("黑色物体", BLACK), ("魔方", CUBE), ("显示器", MON)):
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        span = max(1, h - th)
        print("\n########## %s ##########" % tag)
        for top in range(0, span + 1, max(1, span // 8)):
            px = crop169_at(path, top)
            s = px.astype(np.int16)[::DS, ::DS, :]
            m = classify(s)
            line = "  top=%4d (%3d%%) " % (top, int(100.0 * top / span))
            for k in ("orange", "yg", "dark"):
                bs = stream_bands(m[k], s)
                bs = [b for b in bs if b["cnt"] >= 25]
                bs.sort(key=lambda b: -b["cnt"])
                if bs:
                    b = bs[0]
                    extra = ""
                    if "mx_mean" in b:
                        extra = " mx=%.0f/%.0f chr=%.0f/%.0f br=%.2f" % (
                            b["mx_mean"], b["mx_p95"], b["ch_mean"], b["ch_p95"],
                            b["bright_ratio"])
                    line += " | %s n=%d %dx%d d=%.2f%s" % (
                        k, b["cnt"], b["w"], b["h"], b["dens"], extra)
                else:
                    line += " | %s -" % k
            print(line)


if __name__ == "__main__":
    main()
