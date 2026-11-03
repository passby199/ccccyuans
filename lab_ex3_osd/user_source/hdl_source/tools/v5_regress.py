#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v5_regress.py -- v5 模型的全窗口回归测试

对每张现场照片枚举所有 16:9 裁切窗口，统计：
  - 正样本：该类目标在多少比例的窗口里被检出（框落在目标上）
  - 负样本(显示器)：误检次数必须为 0
"""
import os
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v5_model import (crop169_at, detect, detect_all_bands, CFG)

SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
MON   = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")

# 真值框（网格坐标，来自人工核对图片）
GT = {
    "screw": ("orange", (62, 82, 10, 80)),   # 橙色握把
    "black": ("dark",   (36, 97,  0, 58)),   # 黑方块（手捏黑物）
    "cube":  ("yg",     ( 6, 124, 0, 90)),   # 魔方主体
}


def iou(a, b):
    ax0, ax1, ay0, ay1 = a
    bx0, bx1, by0, by1 = b
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = ix1 - ix0 + 1, iy1 - iy0 + 1
    if iw <= 0 or ih <= 0:
        return 0.0
    inter = iw * ih
    ua = (ax1 - ax0 + 1) * (ay1 - ay0 + 1)
    ub = (bx1 - bx0 + 1) * (by1 - by0 + 1)
    return inter / float(ua + ub - inter)


def run():
    print("=" * 100)
    print("v5 模型全窗口回归")
    print("=" * 100)
    for tag, path in (("screw", SCREW), ("black", BLACK), ("cube", CUBE)):
        cls, gt = GT[tag]
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        span = max(1, h - th)
        hit = 0
        tot = 0
        best_ious = []
        print("\n----- %s (目标类=%s) -----" % (tag, cls))
        for i in range(21):
            top = int(span * i / 20.0)
            px = crop169_at(path, top)
            r = detect(px)
            b = r[cls]
            tot += 1
            if b:
                hb = b["halo_box"]
                ov = iou(hb, gt)
                best_ious.append(ov)
                # IoU 用 GT(目标) 与 halo 框；目标可能只占部分画面
                cov = iou(hb, gt)
                ok = ov > 0.15
                if ok:
                    hit += 1
                print("   top=%3d%%  box=%s core=%d solid=%.2f  IoU=%.2f %s"
                      % (int(100.0 * i / 20.0), hb, b["core"], b["core_solid"],
                         ov, "OK" if ok else "--"))
            else:
                print("   top=%3d%%  未检出" % (int(100.0 * i / 20.0)))
        print("   => 命中 %d / %d 窗口" % (hit, tot))

    print("\n----- 显示器(负样本) 误检检查 -----")
    im = Image.open(MON).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    span = max(1, h - th)
    fp = 0
    for i in range(21):
        top = int(span * i / 20.0)
        px = crop169_at(MON, top)
        r = detect(px)
        if any(r.values()):
            fp += 1
            print("   top=%3d%%  误检: " % (int(100.0 * i / 20.0)) +
                  " ".join("%s=%s" % (k, r[k]["halo_box"]) for k in r if r[k]))
    print("   => 误检窗口 %d / 21" % fp)


if __name__ == "__main__":
    run()
