#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v7_eval.py -- v7 模型的评估（逐 band 诊断 + IoU + 真值）
"""
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v7_model as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out_eval")

CLS_CN = {"boat": "改锥", "blue": "魔方", "dark": "黑色物体"}

TRUTH = {
    "改锥":     dict(box=(504, 136, 647, 607), cls="boat"),
    "魔方":     dict(box=(64, 0, 983, 719),    cls="blue"),
    "黑色物体": dict(box=(360, 0, 767, 591),    cls="dark"),
    "显示器":   dict(box=None, cls=None),
}
SCENES = ["改锥", "魔方", "黑色物体", "显示器"]


def iou(a, bx0, bx1, by0, by1):
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
    print("=" * 100)
    print("v7 模型评估")
    print("=" * 100)
    ok_all = True
    for name in SCENES:
        px = M.V6.load_default(os.path.join(OUT, "win_%s.png" % name))
        res = M.detect(px)
        truth = TRUTH[name]
        print("-" * 100)
        print("场景 %s" % name)
        for k in ("boat", "blue", "dark"):
            b = res[k]
            if b is None:
                print("    %-8s : 未检出" % CLS_CN[k])
                continue
            bx0, bx1, by0, by1, bc = b
            w = bx1 - bx0 + 1
            h = by1 - by0 + 1
            pb = (bx0 * 8, bx1 * 8 + 7, by0 * 8, by1 * 8 + 7)
            ov = 0.0
            if truth.get("box"):
                tb = truth["box"]
                ov = iou(pb, tb[0], tb[2], tb[1], tb[3])
            print("    %-8s : 检出  halo框(格)=(%3d,%3d)-(%3d,%3d) 像素=(%4d,%4d)-(%4d,%4d)"
                  % (CLS_CN[k], bx0, by0, bx1, by1, pb[0], pb[2], pb[1], pb[3]))
            print("              w=%3d h=%3d core=%5d 密实度=%.3f  IoU=%.3f"
                  % (w, h, bc, bc / float(w * h), ov))

        if truth.get("box") is None:
            any_hit = any(res[k] is not None for k in res)
            print("    >>> 负样本：%s" % ("误检！" if any_hit else "正确（无检出）"))
            if any_hit:
                ok_all = False
        else:
            want = truth["cls"]
            if res[want] is None:
                print("    >>> 期望 %s：漏检" % CLS_CN[want])
                ok_all = False
            else:
                others = [c for c in ("boat", "blue", "dark") if c != want and res[c] is not None]
                print("    >>> 期望 %s：检出%s"
                      % (CLS_CN[want], ("，但另外还检出：" + ",".join(CLS_CN[c] for c in others)) if others else ""))
                if others:
                    ok_all = False
    print("=" * 100)
    print("总判定：%s" % ("全部通过" if ok_all else "存在问题"))


if __name__ == "__main__":
    main()
