#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
cc_stats.py -- 连通块级量化：目标 vs 干扰源的统计差异

目的
---------------------------------------------------------------------------
1) 黑色方块 vs 键盘暗区：颜色阈值上二者接近（mx 26 vs 42），
   需要靠【形状/填充率/紧致度】区分。
2) 魔方：黄绿面与绿面颜色接近，但两者都属于魔方 —— 说明"魔方"不能
   只靠单一颜色，需要靠【大块 + 高饱和 + 多色共存】。
3) 改锥：橙色握把孤立，判据已足够。
本脚本输出每个连通块的 位置/尺寸/像素数/填充率/平均RGB/最大RGB。
"""
import os
import sys
import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90

SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
MON   = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")


def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def grid(px):
    return px.astype(np.int16)[::DS, ::DS, :]


def mask_of(s, kind):
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    if kind == "orange":
        return (r >= g) & (r >= b) & ((r - b) >= 60) & ((r - g) >= 45) & (r >= 140)
    if kind == "yg":
        return (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= 60)
    if kind == "dark":
        return (mx < 40) & (chroma < 24)
    if kind == "dark30":
        return (mx < 30) & (chroma < 18)
    if kind == "blue":
        return (b > r) & (b >= g) & (chroma >= 60)
    raise ValueError(kind)


def components(mask, s, min_px=25):
    """4-邻接连通域（纯 numpy BFS）"""
    lab = np.zeros(mask.shape, np.int32)
    cur = 0
    comps = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]:
            continue
        cur += 1
        stack = [(y0, x0)]
        lab[y0, x0] = cur
        pix = []
        while stack:
            y, x = stack.pop()
            pix.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = cur
                    stack.append((ny, nx))
        if len(pix) >= min_px:
            arr = np.array(pix)
            y0, y1 = int(arr[:, 0].min()), int(arr[:, 0].max())
            x0, x1 = int(arr[:, 1].min()), int(arr[:, 1].max())
            area = (y1 - y0 + 1) * (x1 - x0 + 1)
            rgbs = s[arr[:, 0], arr[:, 1]]
            comps.append({
                "n": len(pix), "x0": x0, "x1": x1, "y0": y0, "y1": y1,
                "w": x1 - x0 + 1, "h": y1 - y0 + 1,
                "fill": len(pix) / area,
                "rgb": tuple(int(v) for v in rgbs.mean(axis=0)),
                "mx": int(rgbs.max(axis=0).max()),
                "chroma": int(rgbs.max(axis=0).max() - rgbs.min(axis=0).min()),
            })
    comps.sort(key=lambda c: -c["n"])
    return comps


def show(tag, path, top, kinds):
    print("\n===== %s  window top=%d =====" % (tag, top))
    s = grid(crop169_at(path, top))
    for k in kinds:
        m = mask_of(s, k)
        cs = components(m, s)
        tot = int(m.sum())
        print("  [%s] 总命中=%d  连通块(>=25px)=%d" % (k, tot, len(cs)))
        for c in cs[:6]:
            print("     n=%-6d box=(x%d..%d,y%d..%d) %dx%d fill=%.2f rgb=%s mx=%d chroma=%d"
                  % (c["n"], c["x0"], c["x1"], c["y0"], c["y1"], c["w"], c["h"],
                     c["fill"], c["rgb"], c["mx"], c["chroma"]))


def main():
    show("改锥", SCREW, 150, ["orange", "yg", "dark"])
    show("黑色物体", BLACK, 1050, ["dark", "dark30", "orange", "yg"])
    show("魔方", CUBE, 714, ["yg", "blue", "orange", "dark"])
    show("显示器(干扰)", MON, 0, ["orange", "yg", "blue", "dark"])


if __name__ == "__main__":
    main()
