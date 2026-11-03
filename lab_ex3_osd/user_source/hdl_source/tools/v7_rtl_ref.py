#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v7_rtl_ref.py -- v7 算法的【RTL 等价参考实现】（逐拍语义）

===========================================================================
这个文件是 RTL 的"行为说明书"。RTL 写完后，用 v7_ref_check.py 逐拍对拍。
===========================================================================

RTL 结构（每类一套，三类并行）
---------------------------------------------------------------------------
  阶段1  采样：de && x%8==0 && y%8==0 -> 一个 8x8 格
          判色 -> halo_hit / core_hit

  阶段2  行内最长连续段（streaming，1 拍 1 格）
          run_state: RUN_IDLE / RUN_ACTIVE
            RUN_IDLE: 遇 halo_hit -> RUN_ACTIVE, run_x0=x, run_len=1, run_core=core_hit
            RUN_ACTIVE: halo_hit -> run_len++, run_core += core_hit
                        !halo_hit -> 段结束，结算 best_run（若 run_len 更大），
                                    然后 RUN_IDLE
          best_run: (bx, blen, bcore)  行内最长段的起点/长度/其中core数
          ⚠ 注意："最长段"用 > 比较（与 Python 的 max 保持首个最大值一致）

  阶段3  行末（row_end，本行最后一格之后）
          若 RUN_ACTIVE（段延伸到行末）-> 结算 best_run
          然后用 best_run 做 band 合并（见阶段4）

  阶段4  band 合并
          若 best_len >= PROJ_TH:
             若无当前 band -> 开新 band: bx0=best_x, bx1=best_x+best_len-1,
                                     by0=by1=y, bcore=best_core
             否则若与当前 band 横向重叠(含 GAPX 容差) -> 并入:
                                     bx0=min, bx1=max, by1=y, bcore+=best_core
             否则 -> 收尾旧 band（送入候选），开新 band
             last_hit_y = y
          否则（本行无有效段）:
             若有 band 且 (y - last_hit_y) > VGAP -> 收尾 band

  阶段5  帧末（frame_end）
          收尾当前 band -> 该 band 进候选
          所有候选里取 core 最多的那个（> 比较，首个最大值优先）
          过门限 -> 输出框

  阶段6  门限（对最终选中 band）
          core >= min_core
          core >= K*w 且 core >= K*h     （双轴密度，无乘法器）
          min_w <= w <= max_w, min_h <= h <= max_h

  阶段7  帧间保持
          检出不成立时保持 HOLD_N 帧
"""

import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v7_model as M

DS = 8
W, H = 160, 90


class ClassTracker(object):
    """单类的 RTL 等价状态机（Python 参考）"""

    def __init__(self, cfg, name=""):
        self.cfg = cfg
        self.name = name
        self.reset()

    def reset(self):
        # 阶段2 行内
        self.run_active = False
        self.run_x0 = 0
        self.run_len = 0
        self.run_core = 0
        self.best_x = 0
        self.best_len = 0
        self.best_core = 0
        # 阶段4 band
        self.band_active = False
        self.bx0 = 0
        self.bx1 = 0
        self.by0 = 0
        self.by1 = 0
        self.bcore = 0
        self.last_hit_y = -99
        # 阶段5 候选
        self.cand_core = 0
        self.cand_valid = False
        self.cand = None          # (bx0,bx1,by0,by1,core)
        # 输出
        self.out_valid = False
        self.out_box = None
        self.miss = 0

    # ---- 阶段2：喂一格 ----
    def feed_cell(self, x, halo, core):
        if halo:
            if not self.run_active:
                self.run_active = True
                self.run_x0 = x
                self.run_len = 1
                self.run_core = 1 if core else 0
            else:
                self.run_len += 1
                if core:
                    self.run_core += 1
        else:
            if self.run_active:
                self._close_run()

    def _close_run(self):
        if self.run_len > self.best_len:
            self.best_len = self.run_len
            self.best_x = self.run_x0
            self.best_core = self.run_core
        self.run_active = False

    # ---- 阶段3：行末 ----
    def row_end(self, y):
        if self.run_active:
            self._close_run()
        # 用 best_run 做 band 合并
        if self.best_len >= M.PROJ_TH:
            bx = self.best_x
            bx1 = self.best_x + self.best_len - 1
            bc = self.best_core
            if not self.band_active:
                self.band_active = True
                self.bx0 = bx
                self.bx1 = bx1
                self.by0 = y
                self.by1 = y
                self.bcore = bc
            elif (bx <= self.bx1 + M.GAPX) and (bx1 + M.GAPX >= self.bx0):
                if bx < self.bx0:
                    self.bx0 = bx
                if bx1 > self.bx1:
                    self.bx1 = bx1
                self.by1 = y
                self.bcore += bc
            else:
                self._close_band()
                self.band_active = True
                self.bx0 = bx
                self.bx1 = bx1
                self.by0 = y
                self.by1 = y
                self.bcore = bc
            self.last_hit_y = y
        else:
            if self.band_active and (y - self.last_hit_y) > M.VGAP:
                self._close_band()
                self.band_active = False
        # 清行内状态
        self.best_len = 0
        self.best_x = 0
        self.best_core = 0

    def _close_band(self):
        if self.bcore > 0:
            if (not self.cand_valid) or (self.bcore > self.cand_core):
                self.cand_valid = True
                self.cand_core = self.bcore
                self.cand = (self.bx0, self.bx1, self.by0, self.by1, self.bcore)

    # ---- 阶段5：帧末 ----
    def frame_end(self):
        if self.band_active:
            self._close_band()
            self.band_active = False
        ok = M.gate(self.cand, self.cfg)
        if ok:
            self.out_valid = True
            self.out_box = self.cand[:4]
            self.miss = 0
        else:
            if self.miss < 30:
                self.miss += 1
            else:
                self.out_valid = False
                self.out_box = None
        # 复位帧级状态（行内状态由 row_end 清）
        self.cand_valid = False
        self.cand = None
        self.cand_core = 0
        self.run_active = False


def run_frame(px, cfg_map):
    """逐行逐格跑完整一帧，返回每类结果"""
    s = px.astype(np.int32)[::DS, ::DS, :]
    m = M.classify(s)
    trackers = {k: ClassTracker(cfg_map[k], k) for k in ("boat", "blue", "dark")}
    for y in range(H):
        for k in trackers:
            tr = trackers[k]
            halo = m[k][0][y]
            core = m[k][1][y]
            for x in range(W):
                tr.feed_cell(x, bool(halo[x]), bool(core[x]))
            tr.row_end(y)
    for k in trackers:
        trackers[k].frame_end()
    return {k: (trackers[k].out_box if trackers[k].out_valid else None)
            for k in trackers}


if __name__ == "__main__":
    HERE = os.path.dirname(os.path.abspath(__file__))
    OUT = os.path.join(HERE, "..", "out_eval")
    for name in ["改锥", "魔方", "黑色物体", "显示器"]:
        px = M.V6.load_default(os.path.join(OUT, "win_%s.png" % name))
        r = run_frame(px, M.CFG)
        print("%-10s %s" % (name, {k: v for k, v in r.items()}))
