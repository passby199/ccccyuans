#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_eval.py -- 用【真实 FPGA 截图】验证 v6 判据 + v5 几何算法

验证对象：
  out_eval/win_改锥.png / win_魔方.png / win_黑色物体.png / win_显示器.png
  （FPGA 直出画面，1280x720，显示域 -> 反算回 raw 域）

关键检查项：
  1) 目标是否被检出（valid）
  2) 框是否落在【目标】上，而不是背景（框与真值区域的重叠率）
  3) 负样本（win_显示器）是否【不】检出魔方
"""

import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import v6_model as M
try:
    from scipy import ndimage
except Exception:
    ndimage = None

OUT = os.path.join(os.path.dirname(HERE), "out_eval")

# 真值 ROI（人工标注：目标在画面里的位置，1280x720 显示域坐标）
# 说明：这些 win_*.png 是【裁剪过】的窗口图（名字就叫 win_），目标在画面中部偏左
TRUTH = {
    # ★ 真值已按 out_eval/seg_P*.png 精确分割图 + v6 渲染图人工复核修正
    #   改锥    : 橙色手柄 (504,136)-(647,607)
    #   魔方    : 魔方主体 (64,0)-(983,719)  —— 魔方本就占画面左侧约 78%
    #   黑色物体: 黑色3D块 (360,0)-(767,591)
    "改锥":     dict(box=(504, 136, 647, 607), cls="orange"),
    "魔方":     dict(box=(64, 0, 983, 719),    cls="yg"),
    "黑色物体": dict(box=(360, 0, 767, 591),    cls="dark"),
    "显示器":   dict(box=None, cls=None),          # 负样本：期望全部不检出
}

SCENES = [
    ("改锥",     "win_改锥.png"),
    ("魔方",     "win_魔方.png"),
    ("黑色物体", "win_黑色物体.png"),
    ("显示器",   "win_显示器.png"),
]

CLS_CN = {"orange": "改锥", "yg": "魔方", "dark": "黑色物体"}


def iou(a, bx0, bx1, by0, by1):
    """a=(x0,x1,y0,y1)；另一框以 (bx0,bx1,by0,by1) 传入"""
    if a is None:
        return 0.0
    ax0, ax1, ay0, ay1 = a
    ix0, ix1 = max(ax0, bx0), min(ax1, bx1)
    iy0, iy1 = max(ay0, by0), min(ay1, by1)
    if ix1 < ix0 or iy1 < iy0:
        return 0.0
    inter = (ix1 - ix0 + 1) * (iy1 - iy0 + 1)
    ua = (ax1 - ax0 + 1) * (ay1 - ay0 + 1)
    ub = (bx1 - bx0 + 1) * (by1 - by0 + 1)
    return inter / float(ua + ub - inter)


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    print("=" * 104)
    print("v6 判据 + v5 几何算法 在真实 FPGA 截图上的表现")
    print("=" * 104)

    for name, fn in SCENES:
        if only and only not in name:
            continue
        path = os.path.join(OUT, fn)
        if not os.path.exists(path):
            print("!! 缺", path)
            continue

        disp = np.asarray(Image.open(path).convert("RGB").resize((1280, 720), Image.BILINEAR))
        raw = M.disp_to_raw(disp)
        truth = TRUTH.get(name, {})

        print("-" * 104)
        print("场景 %s   (%s)" % (name, fn))
        if truth.get("box"):
            tb = truth["box"]
            print("  真值框(显示域) = (%d,%d)-(%d,%d)   期望类别 = %s"
                  % (tb[0], tb[1], tb[2], tb[3], CLS_CN[truth["cls"]]))
        else:
            print("  真值框 = 无（负样本，期望【不检出】任何类别）")
            tb = None

        res = M.detect(raw)
        any_hit = False
        for k in ("orange", "yg", "dark"):
            b = res[k]
            if b is None:
                print("    %-8s : 未检出" % CLS_CN[k])
                continue
            any_hit = True
            hb = b["halo_box"]
            # halo_box 是 160x90 网格坐标 -> 1280x720 像素
            pb = (hb[0] * 8, hb[1] * 8 + 7, hb[2] * 8, hb[3] * 8 + 7)
            ov = iou(pb, tb[0], tb[2], tb[1], tb[3]) if tb else 0.0
            cb = b["core_box"]
            cpb = (cb[0] * 8, cb[1] * 8 + 7, cb[2] * 8, cb[3] * 8 + 7)
            print("    %-8s : 检出  halo(网格)=(%3d,%3d)-(%3d,%3d) 像素=(%4d,%4d)-(%4d,%4d)"
                  % (CLS_CN[k], hb[0], hb[2], hb[1], hb[3], pb[0], pb[2], pb[1], pb[3]))
            print("              core(网格)=(%3d,%3d)-(%3d,%3d) core数=%5d 密实度=%.3f  "
                  "core_w=%3d core_h=%3d  与真值 IoU=%.3f"
                  % (cb[0], cb[2], cb[1], cb[3], b["core"], b["core_solid"],
                     b["core_w"], b["core_h"], ov))

        if tb is None:
            print("    >>> 负样本：%s" % ("误检！" if any_hit else "正确（无检出）"))
        else:
            want = truth["cls"]
            ok = res[want] is not None
            if ok:
                hb = res[want]["halo_box"]
                pb = (hb[0] * 8, hb[1] * 8 + 7, hb[2] * 8, hb[3] * 8 + 7)
                ov = iou(pb, tb[0], tb[2], tb[1], tb[3])
                print("    >>> 期望类别 %s：%s（与真值 IoU=%.3f）"
                      % (CLS_CN[want], "检出" if ok else "漏检", ov))
                others = [c for c in ("orange", "yg", "dark") if c != want and res[c] is not None]
                if others:
                    print("        但另外还检出：%s" % ", ".join(CLS_CN[c] for c in others))
            else:
                print("    >>> 期望类别 %s：漏检" % CLS_CN[want])
        print()


if __name__ == "__main__":
    main()
