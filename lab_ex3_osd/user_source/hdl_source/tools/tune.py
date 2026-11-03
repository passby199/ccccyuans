#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
tune.py -- 门限扫描：为每类找"正样本全过、负样本全不过"的门限组合

判据（每类独立）：
  core 数 >= min_core
  core 包围盒密实度 >= min_csolid
  core 包围盒宽 >= min_w、高 >= min_h
  core 包围盒宽 <= max_w、高 <= max_h

对 dark 类额外扫描 min_w / min_csolid / min_core 组合，找出既保正样本、
又压掉显示器暗区误检的门限。
"""
import os
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v5_model as M

SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
MON   = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

CASES = [("screw", SCREW, "orange"), ("black", BLACK, "dark"), ("cube", CUBE, "yg")]
NEG = ("mon", MON)


def windows(path, n=21):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    span = max(1, h - th)
    return [M.crop169_at(path, int(span * i / (n - 1.0))) for i in range(n)]


def bands_for(wins, cls):
    """预计算每窗口每类的所有 band（含未过门限的），供快速扫描"""
    out = []
    for px in wins:
        s = px.astype(np.int32)[::M.DS, ::M.DS, :]
        m = M.classify(s)
        halo, core = m[cls]
        out.append(M.detect_class(halo, core, M.CFG[cls]))
    return out


def main():
    print("预计算所有窗口的 band ...")
    data = {}
    for tag, path, cls in CASES:
        data[(tag, cls)] = bands_for(windows(path), cls)
    neg = bands_for(windows(MON), "dark")
    neg_o = bands_for(windows(MON), "orange")
    neg_y = bands_for(windows(MON), "yg")

    # -------- dark 类门限扫描 --------
    print("\n=========== dark 门限扫描 ===========")
    print("  目标：正样本(black) 有效检出 >= 6/21 窗口，且 显示器误检 = 0")
    best = []
    for min_core in (40, 60, 80, 120, 200, 300):
        for min_csolid in (0.40, 0.45, 0.50, 0.55, 0.60):
            for min_w in (6, 10, 14, 18, 22, 26):
                cfg = dict(min_core=min_core, min_csolid=min_csolid,
                           min_w=min_w, min_h=4, max_w=120, max_h=90)
                ph = sum(1 for b in data[("black", "dark")] if M.gate(b, cfg))
                fp = sum(1 for b in neg if M.gate(b, cfg))
                if fp == 0:
                    best.append((ph, min_core, min_csolid, min_w))
    best.sort(reverse=True)
    for r in best[:14]:
        print("   正样本命中=%2d/21  min_core=%3d min_csolid=%.2f min_w=%2d" % r)
    if not best:
        print("   无组合能做到零误检")
        # 打印误检来源
        for i, b in enumerate(neg):
            if b and b["ok"]:
                print("     误检窗口 %d: core=%d solid=%.2f corebox=%dx%d"
                      % (i, b["core"], b["core_solid"], b["core_w"], b["core_h"]))

    # -------- orange / yg ---------
    for cls, key in (("orange", ("screw", "orange")), ("yg", ("cube", "yg"))):
        negset = neg_o if cls == "orange" else neg_y
        print("\n=========== %s 门限扫描 ===========" % cls)
        rows = []
        for min_core in (10, 20, 30, 50, 80, 120):
            for min_csolid in (0.30, 0.40, 0.45, 0.50, 0.60):
                for min_w in (4, 8, 12, 16):
                    cfg = dict(min_core=min_core, min_csolid=min_csolid,
                               min_w=min_w, min_h=4, max_w=160, max_h=90)
                    ph = sum(1 for b in data[key] if M.gate(b, cfg))
                    fp = sum(1 for b in negset if M.gate(b, cfg))
                    if fp == 0:
                        rows.append((ph, min_core, min_csolid, min_w))
        rows.sort(reverse=True)
        for r in rows[:10]:
            print("   正样本命中=%2d/21  min_core=%3d min_csolid=%.2f min_w=%2d" % r)
        if not rows:
            print("   无零误检组合")


if __name__ == "__main__":
    main()
