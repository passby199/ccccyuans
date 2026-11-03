#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v7_rtl_sim.py -- 严格照 param_ctrl.v 里 v7_class 的 RTL 逐拍语义重写一遍

目的：本机没有 iverilog / verilator，用这个 Python 版 RTL 模拟器代替仿真，
      验证「五级流水 RTL」与「v7_model 的算法」逐像素一致。

RTL 五级流水（每级 1 拍）：
  A  sample 拍        : run 累加 / 段自然结束时结算 best
  B  row_end+1 拍     : 段延伸到行末 -> 结算 best
  C  row_end+2 拍     : 用 best 做 band 合并
  D  frame_end 拍     : 收当前 band -> 候选
  E  frame_end+1 拍   : 门限判定 + 帧间保持 + 输出

事件序列（与 target_detect 里生成的脉冲完全一致）：
  每行 y = 0..89：
    x = 0..158 : sample
    x = 159   : sample + row_end
    再 1 拍    : row_end_d1
    再 1 拍    : row_end_d2
  所有行跑完：
    1 拍       : frame_end
    再 1 拍    : frame_end_d1
"""

import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v7_model as M

DS = 8
W, H = 160, 90
SAT = 2047         # bcore/cand_core 的 11 位饱和上限


class V7ClassRTL(object):
    """param_ctrl.v 里 v7_class 的逐拍等价模型（五级流水版）"""

    def __init__(self, cfg, min_core=15):
        self.cfg = cfg
        self.min_core = min_core
        # A+B
        self.run_act = 0
        self.run_x0 = 0
        self.run_len = 0
        self.run_core = 0
        self.best_x = 0
        self.best_len = 0
        self.best_core = 0
        # 行内统计（整行最左/最右/命中数）
        self.l_min = 255
        self.l_max = 0
        self.l_cnt = 0
        self.l_ccnt = 0
        # 行结果
        self.row_valid = 0
        self.row_x0 = self.row_x1 = 0
        self.row_ccnt = 0
        # C
        self.band_act = 0
        self.bx0 = self.bx1 = 0
        self.by0 = self.by1 = 0
        self.bcore = 0
        self.last_y = 0
        # D
        self.cand_valid = 0
        self.cand_core = 0
        self.cand_x0 = self.cand_x1 = 0
        self.cand_y0 = self.cand_y1 = 0
        # E
        self.miss = 0
        self.out_valid = 0
        self.out_box = None
        self.pass_ = 0
        self.gcore = 0

    # ------------------------------------------------------------------
    def clock(self, sample, row_end_d1, row_end_d2,
              frame_end, frame_end_d1, sx, sy, hit, core):
        """一个时钟沿"""
        cfg = self.cfg
        HOLD_N = 30
        PROJ_TH = M.PROJ_TH
        GAPX = M.GAPX
        VGAP = M.VGAP

        # ============ A + B：行内最长连续段 ============
        if sample:
            # 行内统计
            if hit:
                if self.l_cnt == 0:
                    self.l_min = sx
                    self.l_max = sx
                else:
                    if sx < self.l_min: self.l_min = sx
                    if sx > self.l_max: self.l_max = sx
                self.l_cnt += 1
                self.l_ccnt += 1 if core else 0
            # 最长连续段
            if hit:
                if not self.run_act:
                    self.run_act = 1
                    self.run_x0 = sx
                    self.run_len = 1
                    self.run_core = 1 if core else 0
                else:
                    self.run_len += 1
                    self.run_core += 1 if core else 0
            elif self.run_act:
                self.run_act = 0
                if self.run_len > self.best_len:
                    self.best_len = self.run_len
                    self.best_x = self.run_x0
                    self.best_core = self.run_core
        elif row_end_d1:
            # ① 收段（先算「收段后」的 best 组合值）
            closing = self.run_act and (self.run_len > self.best_len)
            bs_len  = self.run_len  if closing else self.best_len
            bs_x    = self.run_x0   if closing else self.best_x
            bs_core = self.run_core if closing else self.best_core
            if self.run_act:
                self.run_act = 0
                if self.run_len > self.best_len:
                    self.best_len = self.run_len
                    self.best_x = self.run_x0
                    self.best_core = self.run_core
            # ② 决定本行用哪一段
            if (self.l_cnt >= PROJ_TH and
                    self.l_cnt * 2 >= (self.l_max - self.l_min + 1)):
                self.row_valid = 1
                self.row_x0, self.row_x1 = self.l_min, self.l_max
                self.row_ccnt = self.l_ccnt
            elif bs_len >= PROJ_TH:
                self.row_valid = 1
                self.row_x0, self.row_x1 = bs_x, bs_x + bs_len - 1
                self.row_ccnt = bs_core
            else:
                self.row_valid = 0
            # ③ 清行内统计
            self.l_min, self.l_max = 255, 0
            self.l_cnt, self.l_ccnt = 0, 0

        # ============ C / D / E（互斥分支）============
        if row_end_d2:
            bc_new = min(self.bcore + self.row_ccnt, SAT)
            if self.row_valid:
                if not self.band_act:
                    self.band_act = 1
                    self.bx0 = self.row_x0
                    self.bx1 = self.row_x1
                    self.by0 = sy
                    self.by1 = sy
                    self.bcore = self.row_ccnt
                elif (self.row_x0 <= self.bx1 + GAPX) and (self.row_x1 + GAPX >= self.bx0):
                    if self.row_x0 < self.bx0:
                        self.bx0 = self.row_x0
                    if self.row_x1 > self.bx1:
                        self.bx1 = self.row_x1
                    self.by1 = sy
                    self.bcore = bc_new
                else:
                    if self.bcore > 0:
                        if (not self.cand_valid) or (self.bcore > self.cand_core):
                            self.cand_valid = 1
                            self.cand_core = self.bcore
                            self.cand_x0, self.cand_x1 = self.bx0, self.bx1
                            self.cand_y0, self.cand_y1 = self.by0, self.by1
                    self.band_act = 1
                    self.bx0 = self.row_x0
                    self.bx1 = self.row_x1
                    self.by0 = sy
                    self.by1 = sy
                    self.bcore = self.row_ccnt
                self.last_y = sy
            elif self.band_act and ((sy - self.last_y) & 0xFF) > VGAP:
                if self.bcore > 0:
                    if (not self.cand_valid) or (self.bcore > self.cand_core):
                        self.cand_valid = 1
                        self.cand_core = self.bcore
                        self.cand_x0, self.cand_x1 = self.bx0, self.bx1
                        self.cand_y0, self.cand_y1 = self.by0, self.by1
                self.band_act = 0
            # 清行内最长段
            self.best_len = 0
            self.best_x = 0
            self.best_core = 0

        elif frame_end:
            if self.band_act and self.bcore > 0:
                if (not self.cand_valid) or (self.bcore > self.cand_core):
                    self.cand_valid = 1
                    self.cand_core = self.bcore
                    self.cand_x0, self.cand_x1 = self.bx0, self.bx1
                    self.cand_y0, self.cand_y1 = self.by0, self.by1
            self.band_act = 0

        elif frame_end_d1:
            gw = (self.cand_x1 - self.cand_x0 + 1) & 0xFF
            gh = (self.cand_y1 - self.cand_y0 + 1) & 0xFF
            k = cfg["dens_k"]
            kw = min(k * gw, SAT)
            kh = min(k * gh, SAT)
            ar_ok = True
            edge_ok = True
            gate_ok = (self.cand_valid == 1 and
                       self.cand_core >= cfg["min_core"] and
                       self.cand_core >= self.min_core and
                       self.cand_core >= kw and self.cand_core >= kh and
                       gw >= cfg["min_w"] and gw <= cfg["max_w"] and
                       gh >= cfg["min_h"] and gh <= cfg["max_h"] and edge_ok and ar_ok)
            self.pass_ = 1 if gate_ok else 0
            self.gcore = self.cand_core
            if gate_ok:
                self.out_valid = 1
                self.out_box = (self.cand_x0, self.cand_x1,
                                self.cand_y0, self.cand_y1)
                self.miss = 0
            elif self.miss < HOLD_N:
                self.miss += 1
            else:
                self.out_valid = 0
            self.cand_valid = 0
            self.cand_core = 0


def run_frame(px, min_core=15):
    """按 RTL 的脉冲时序跑完一帧"""
    s = px.astype(np.int32)[::DS, ::DS, :]
    m = M.classify(s)
    trs = {k: V7ClassRTL(M.CFG[k], min_core) for k in ("blue", "dark", "red")}

    for y in range(H):
        for k, tr in trs.items():
            halo = m[k][0][y]
            core = m[k][1][y]
            # A：160 个 sample 拍（最后一拍同时是 row_end）
            for x in range(W):
                tr.clock(1, 0, 0, 0, 0, x, y, bool(halo[x]), bool(core[x]))
            # B：row_end+1
            tr.clock(0, 1, 0, 0, 0, 0, y, False, False)
            # C：row_end+2
            tr.clock(0, 0, 1, 0, 0, 0, y, False, False)

    # D：frame_end
    for tr in trs.values():
        tr.clock(0, 0, 0, 1, 0, 0, 0, False, False)
    # E：frame_end+1
    for tr in trs.values():
        tr.clock(0, 0, 0, 0, 1, 0, 0, False, False)

    return {k: (tr.out_box if tr.out_valid else None) for k, tr in trs.items()}, \
           {k: (tr.pass_, tr.gcore) for k, tr in trs.items()}


def main():
    HERE = os.path.dirname(os.path.abspath(__file__))
    OUT = os.path.join(HERE, "..", "out_eval")
    names = ["黑色物体", "显示器"]   # 小船/蓝色暂无 raw 域实测图
    bad = 0
    for name in names:
        px = M.V6.load_default(os.path.join(OUT, "win_%s.png" % name))
        rtl_box, rtl_gate = run_frame(px)
        mdl_box = M.detect(px)
        mdl4 = {k: (None if v is None else v[:4]) for k, v in mdl_box.items()}
        ok = all(rtl_box[k] == mdl4[k] for k in rtl_box)
        if not ok:
            bad += 1
        print("%-10s %s" % (name, "OK " if ok else "MISMATCH"))
        print("           RTL  : %s" % {k: v for k, v in rtl_box.items()})
        print("           MODEL: %s" % {k: v for k, v in mdl4.items()})
        if not ok:
            print("           gate : %s" % {k: v for k, v in rtl_gate.items()})
    print()
    print("RTL vs MODEL: %s" % ("全部一致" if bad == 0 else "%d 处不一致" % bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
