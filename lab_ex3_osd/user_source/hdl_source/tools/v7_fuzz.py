#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v7_fuzz.py -- 随机对抗测试：RTL 逐拍模型 vs 算法模型

真实图片只覆盖 4 个场景，可能漏掉边界情况（多 band、跨行段、band 分裂、
空行容忍、帧末未收 band、尺寸门限卡边……）。这里用随机二值图狂轰，
逐帧比较两者的输出框，确保 RTL 的流式状态机在任何输入下都等价于
v7_model.detect_class + gate。
"""

import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v7_model as M
from v7_rtl_sim import V7ClassRTL, W, H


def model_box(halo, core, cfg):
    b = M.detect_class(halo, core, cfg)
    return b[:4] if (b is not None and M.gate(b, cfg)) else None


def rtl_box(halo, core, cfg, min_core=15):
    tr = V7ClassRTL(cfg, min_core)
    for y in range(H):
        for x in range(W):
            tr.clock(1, 0, 0, 0, 0, x, y, bool(halo[y, x]), bool(core[y, x]))
        tr.clock(0, 1, 0, 0, 0, 0, y, False, False)   # row_end+1
        tr.clock(0, 0, 1, 0, 0, 0, y, False, False)   # row_end+2
    tr.clock(0, 0, 0, 1, 0, 0, 0, False, False)       # frame_end
    tr.clock(0, 0, 0, 0, 1, 0, 0, False, False)       # frame_end+1
    return tr.out_box if tr.out_valid else None


def rand_field(rng, p):
    return rng.random((H, W)) < p


def make_case(rng, kind):
    halo = np.zeros((H, W), dtype=bool)
    core = np.zeros((H, W), dtype=bool)

    if kind == 0:      # 随机稀疏点
        halo = rand_field(rng, rng.uniform(0.005, 0.15))
        core = halo & rand_field(rng, rng.uniform(0.3, 1.0))
    elif kind == 1:    # 若干随机矩形（可能分裂/重叠/贴边）
        for _ in range(rng.integers(1, 6)):
            x0 = rng.integers(0, W - 4); x1 = rng.integers(x0, W)
            y0 = rng.integers(0, H - 4); y1 = rng.integers(y0, H)
            halo[y0:y1 + 1, x0:x1 + 1] = True
            if rng.random() < 0.8:
                core[y0:y1 + 1, x0:x1 + 1] = True
            else:
                core[y0:y1 + 1, x0:x1 + 1] = rand_field(
                    rng, rng.uniform(0.0, 1.0))[y0:y1 + 1, x0:x1 + 1]
    elif kind == 2:    # 多行横条，测试 band 分裂 / 空行容忍
        for _ in range(rng.integers(2, 8)):
            y0 = rng.integers(0, H - 2)
            hgt = rng.integers(1, 6)
            x0 = rng.integers(0, W - 8); x1 = rng.integers(x0 + 4, W)
            halo[y0:min(y0 + hgt, H), x0:x1 + 1] = True
        core = halo & rand_field(rng, rng.uniform(0.2, 1.0))
    elif kind == 3:    # 整行满 / 满屏（测尺寸上限与密度）
        halo[:] = rng.random() < 0.5
        core = halo & rand_field(rng, rng.uniform(0.1, 1.0))
    elif kind == 4:    # 贴边（x=0 / x=159 / y=0 / y=89）
        halo[0, :] = rng.random() < 0.6
        halo[-1, :] = rng.random() < 0.6
        halo[:, 0] = rng.random() < 0.6
        halo[:, -1] = rng.random() < 0.6
        core = halo & rand_field(rng, rng.uniform(0.3, 1.0))
    else:              # 阶梯（每行不同宽度，测 band 逐行并集）
        base = rng.integers(2, W // 2)
        for y in range(H):
            wdt = int(base * (1 + 0.9 * np.sin(y / rng.uniform(2, 12))))
            wdt = max(2, min(W, wdt))
            halo[y, :wdt] = True
        core = halo & rand_field(rng, rng.uniform(0.4, 1.0))

    return halo, core


def main():
    rng = np.random.default_rng(20261029)
    kinds = 6
    total = 0
    bad = 0
    first_bad = None

    for cfg_name in ("blue", "dark", "red"):
        cfg = M.CFG[cfg_name]
        for kind in range(kinds):
            for _ in range(40):
                halo, core = make_case(rng, kind)
                mb = model_box(halo, core, cfg)
                rb = rtl_box(halo, core, cfg)
                total += 1
                if mb != rb:
                    bad += 1
                    if first_bad is None:
                        first_bad = (cfg_name, kind, mb, rb, halo.copy(), core.copy())

    print("随机用例 %d 个，不一致 %d 个" % (total, bad))
    if first_bad is not None:
        cfg_name, kind, mb, rb, halo, core = first_bad
        print("首个不一致: cfg=%s kind=%d" % (cfg_name, kind))
        print("  MODEL: %s" % (mb,))
        print("  RTL  : %s" % (rb,))
        ys, xs = np.where(halo)
        if len(ys):
            print("  halo bbox: x %d..%d  y %d..%d  count=%d"
                  % (xs.min(), xs.max(), ys.min(), ys.max(), len(ys)))
        return 1
    print("结论：RTL 逐拍模型与算法模型在全部随机用例上完全等价")
    return 0


if __name__ == "__main__":
    sys.exit(main())
