#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_probe.py -- ROI 级定量测量
在 raw 域统计指定 ROI 的颜色分布，用来定"黑色物体 vs 键盘"、"绿主导 vs 显示器屏幕"的分界
"""
import os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v6_model as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out_eval")


def stats(name, arr, mask=None):
    a = arr.reshape(-1, 3)
    if mask is not None:
        m = mask.reshape(-1)
        a = a[m]
    if len(a) == 0:
        print("  %-22s EMPTY" % name)
        return
    r, g, b = a[:, 0], a[:, 1], a[:, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    ch = mx - mn
    print("  %-22s n=%6d  R med=%3d  G med=%3d  B med=%3d | mx p5=%3d p50=%3d p95=%3d "
          "| chroma p50=%3d p90=%3d | R-B med=%4d  G-B med=%4d"
          % (name, len(a), np.median(r), np.median(g), np.median(b),
             np.percentile(mx, 5), np.percentile(mx, 50), np.percentile(mx, 95),
             np.percentile(ch, 50), np.percentile(ch, 90),
             np.median(r - b), np.median(g - b)))


def roi(arr, box):
    x0, y0, x1, y1 = box
    return arr[y0:y1, x0:x1]


def load(scene):
    p = os.path.join(OUT, "win_%s.png" % scene)
    px = M.load_default(p)
    return px, M.disp_to_raw(px)


def main():
    print("=" * 100)
    print("A) win_黑色物体.png  —— 目标(黑块) vs 键盘 vs 手指")
    px, raw = load("黑色物体")
    stats("整幅", raw)
    # 黑块（3D打印件）在画面左上，键盘在右下
    for nm, box in [("黑块ROI", (250, 20, 560, 280)),
                    ("黑块核心", (300, 60, 470, 200)),
                    ("键盘区", (760, 380, 1240, 700)),
                    ("键帽区", (850, 100, 1150, 350)),
                    ("手指", (60, 250, 300, 600))]:
        stats(nm, roi(raw, box))

    print()
    print("=" * 100)
    print("B) win_魔方.png  —— 绿/黄绿面 vs 显示器屏幕(蓝白) vs 手指")
    px2, raw2 = load("魔方")
    for nm, box in [("绿面(右下)", (560, 380, 900, 700)),
                    ("黄绿面(顶)", (300, 20, 700, 180)),
                    ("绿面(左)", (80, 220, 380, 620)),
                    ("键盘背景", (900, 100, 1250, 600)),
                    ("手指", (40, 100, 200, 400))]:
        stats(nm, roi(raw2, box))

    print()
    print("=" * 100)
    print("C) win_显示器.png  —— 负样本：屏幕 vs 外壳 vs 桌面")
    px3, raw3 = load("显示器")
    for nm, box in [("笔记本屏幕", (400, 130, 640, 330)),
                    ("蓝标题栏", (430, 240, 560, 300)),
                    ("机身外壳", (750, 200, 1000, 500)),
                    ("桌面暗区", (0, 0, 200, 100)),
                    ("右侧杂物", (950, 260, 1100, 520))]:
        stats(nm, roi(raw3, box))

    print()
    print("=" * 100)
    print("D) win_改锥.png  —— 橙色手柄 vs 灰手套 vs 白色屏幕")
    px4, raw4 = load("改锥")
    for nm, box in [("橙柄", (400, 220, 500, 480)),
                    ("橙柄核心", (410, 300, 490, 420)),
                    ("灰手套", (250, 200, 380, 500)),
                    ("白屏幕", (0, 100, 300, 400)),
                    ("手柄高光", (420, 160, 470, 220))]:
        stats(nm, roi(raw4, box))


if __name__ == "__main__":
    main()
