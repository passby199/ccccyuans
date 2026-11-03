#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v5_final.py -- v5 最终验证：IoU 为主指标 + 负样本零误检

关键点
---------------------------------------------------------------------------
目标物体只在【部分】16:9 窗口里真正可见（照片是竖拍，物体在特定高度）。
所以"命中窗口数"意义有限 —— 必须看【框是否落在物体上】(IoU)。
本脚本：
  1) 对每个窗口算检测框与真值框的 IoU
  2) 只统计"目标可见"的窗口（IoU 意义明确的那些）
  3) 报告：可见窗口命中率、平均 IoU、最差情况
  4) 负样本（显示器）：任何窗口检出都算误检
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

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")

CASES = [
    ("screw", SCREW, "orange", (62, 82, 8, 82)),
    ("black", BLACK, "dark",   (36, 97, 0, 60)),
    ("cube",  CUBE,  "yg",     ( 6, 124, 0, 90)),
]


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


def coverage(box, gt):
    """检测框覆盖真值的比例（真值被框住多少）"""
    bx0, bx1, by0, by1 = box
    gx0, gx1, gy0, gy1 = gt
    ix0, iy0 = max(bx0, gx0), max(by0, gy0)
    ix1, iy1 = min(bx1, gx1), min(by1, gy1)
    iw, ih = ix1 - ix0 + 1, iy1 - iy0 + 1
    if iw <= 0 or ih <= 0:
        return 0.0
    return (iw * ih) / float((gx1 - gx0 + 1) * (gy1 - gy0 + 1))


def run():
    print("=" * 96)
    print("v5 最终验证（IoU 主指标）")
    print("=" * 96)
    summary = []
    for tag, path, cls, gt in CASES:
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        span = max(1, h - th)
        print("\n----- %s  目标类=%s  真值框=%s -----" % (tag, cls, gt))
        rows = []
        for i in range(21):
            top = int(span * i / 20.0)
            px = M.crop169_at(path, top)
            r = M.detect(px)
            b = r[cls]
            if b:
                hb = b["halo_box"]
                v = iou(hb, gt)
                c = coverage(hb, gt)
                rows.append((i * 5, hb, v, c, b["core"], b["core_solid"]))
                print("   %3d%%  box=%-22s IoU=%.2f 覆盖=%.2f core=%d solid=%.2f"
                      % (i * 5, str(hb), v, c, b["core"], b["core_solid"]))
            else:
                rows.append((i * 5, None, 0.0, 0.0, 0, 0))
                print("   %3d%%  未检出" % (i * 5))
        # 只看"目标可见"的窗口：真值框在画面内至少有一部分
        vis = [r for r in rows if r[2] > 0 or r[3] > 0]
        det = [r for r in rows if r[1] is not None]
        print("   检出 %d/21 窗口；其中 IoU>=0.2 的 %d 个；平均 IoU(检出者)=%.3f"
              % (len(det), sum(1 for r in det if r[2] >= 0.2),
                 np.mean([r[2] for r in det]) if det else 0))
        summary.append((tag, len(det), sum(1 for r in det if r[2] >= 0.2)))

    print("\n----- 负样本(显示器)：任何检出都算误检 -----")
    im = Image.open(MON).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    span = max(1, h - th)
    fp = 0
    for i in range(21):
        px = M.crop169_at(MON, int(span * i / 20.0))
        r = M.detect(px)
        if any(r.values()):
            fp += 1
            print("   %3d%%  误检: " % (i * 5) +
                  " ".join("%s=%s core=%d solid=%.2f" %
                           (k, r[k]["halo_box"], r[k]["core"], r[k]["core_solid"])
                           for k in r if r[k]))
    print("   => 误检 %d/21 窗口" % fp)

    print("\n----- 汇总 -----")
    for t, nd, ng in summary:
        print("   %-8s 检出 %2d/21  IoU>=0.2 的 %2d 个" % (t, nd, ng))
    print("   显示器误检 %d/21" % fp)


if __name__ == "__main__":
    run()
