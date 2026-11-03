#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_hist.py -- 黑块 vs 键盘 的 raw 域 (mx, chroma) 分布直方图
寻找干净的可分界
"""
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v6_model as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out_eval")


def load(scene):
    px = M.load_default(os.path.join(OUT, "win_%s.png" % scene))
    return M.disp_to_raw(px)


def region(raw, box):
    x0, y0, x1, y1 = box
    a = raw[y0:y1, x0:x1].reshape(-1, 3).astype(np.int32)
    mx = np.maximum(np.maximum(a[:, 0], a[:, 1]), a[:, 2])
    mn = np.minimum(np.minimum(a[:, 0], a[:, 1]), a[:, 2])
    return a, mx, mx - mn


def show(name, a, mx, ch):
    print("  %-14s n=%6d" % (name, len(a)))
    print("     mx   直方: " + " ".join("%d:%d" % (v, int((mx == v).sum())) for v in range(10, 55)))
    print("     chroma直方: " + " ".join("%d:%d" % (v, int((ch == v).sum())) for v in range(0, 30)))
    ratio = ch.astype(np.float64) / np.maximum(mx, 1)
    print("     chroma/mx 分位: p10=%.3f p25=%.3f p50=%.3f p75=%.3f p90=%.3f"
          % tuple(np.percentile(ratio, [10, 25, 50, 75, 90])))
    # 联合判据 mx<TH & chroma<SAT 的命中率
    for th, sat in ((40, 24), (36, 20), (32, 16), (30, 12), (28, 10), (26, 8)):
        hit = ((mx < th) & (ch < sat)).mean()
        print("       mx<%2d & chroma<%2d -> 命中率 %6.2f%%" % (th, sat, hit * 100))


def main():
    raw = load("黑色物体")
    print("=" * 100)
    print("A) 黑色物体场景")
    # 真黑块：网格 c7 列 x=560..640, y=0..240 （黑色3D件），加一点余量
    a, mx, ch = region(raw, (555, 0, 650, 245))
    show("真黑块", a, mx, ch)
    a, mx, ch = region(raw, (820, 0, 1260, 700))
    show("键盘整体", a, mx, ch)
    a, mx, ch = region(raw, (900, 60, 1250, 420))
    show("键帽区", a, mx, ch)

    raw2 = load("改锥")
    print()
    print("=" * 100)
    print("B) 改锥场景 —— 暗区（手套/桌面）会不会被判成黑色")
    a, mx, ch = region(raw2, (250, 120, 400, 600))
    show("灰手套", a, mx, ch)
    a, mx, ch = region(raw2, (0, 620, 400, 720))
    show("下缘暗区", a, mx, ch)

    raw3 = load("魔方")
    print()
    print("=" * 100)
    print("C) 魔方场景 —— 键盘背景 / 绿面")
    a, mx, ch = region(raw3, (900, 60, 1250, 600))
    show("键盘背景", a, mx, ch)
    a, mx, ch = region(raw3, (560, 380, 900, 700))
    show("绿面", a, mx, ch)

    raw4 = load("显示器")
    print()
    print("=" * 100)
    print("D) 显示器场景 —— 负样本")
    a, mx, ch = region(raw4, (0, 0, 1280, 60))
    show("顶部暗带", a, mx, ch)
    a, mx, ch = region(raw4, (960, 380, 1120, 720))
    show("右侧暗物", a, mx, ch)


if __name__ == "__main__":
    main()
