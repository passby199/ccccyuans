#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_diag.py -- 逐 band 诊断：用数据定阈值，而不是猜

对每个场景、每个类别，列出所有 band 的几何特征：
    halo 框（网格）/ core 框 / core 像素数 / 密实度 / 宽高 / 面积占比

用法：
    python tools/v6_diag.py              # 全部场景
    python tools/v6_diag.py 改锥          # 只看一个场景
"""

import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v6_model as M

OUT = os.path.join(os.path.dirname(HERE), "out_eval")
SCENES = [
    ("改锥", "win_改锥.png"),
    ("魔方", "win_魔方.png"),
    ("黑色物体", "win_黑色物体.png"),
    ("显示器", "win_显示器.png"),
]
CLS_CN = {"orange": "改锥", "yg": "魔方", "dark": "黑色物体"}


def band_list(px):
    """返回每类全部 band（含未过 gate 的），按 core 数排序"""
    s = px.astype(np.int32)[::M.DS, ::M.DS, :]
    m = M.classify(s)
    out = {}
    for k in ("orange", "yg", "dark"):
        # 复制 detect_class 的逻辑但保留全部 band
        out[k] = all_bands(m[k][0], m[k][1])
    return out


def all_bands(halo, core):
    bands = []
    active = False
    bx0 = bx1 = by0 = by1 = 0
    cx0 = cx1 = cy0 = cy1 = 0
    bcore = 0
    c_any = False
    last = -99
    for y in range(M.H):
        cl = M.row_clusters(halo[y])
        crow = core[y]
        if cl:
            bc = max(cl, key=lambda t: t[2])
            blo, bhi, bcnt = bc
            sub = crow[blo:bhi + 1]
            cidx = np.nonzero(sub)[0]
            if len(cidx):
                c_lo = int(cidx.min()) + blo
                c_hi = int(cidx.max()) + blo
                c_cnt = int(len(cidx))
            else:
                c_lo = c_hi = blo
                c_cnt = 0
        else:
            blo = bhi = bcnt = 0
            c_lo = c_hi = 0
            c_cnt = 0

        if bcnt >= M.PROJ_TH:
            if not active:
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt
                c_any = c_cnt > 0
                if c_any:
                    cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            elif blo <= bx1 + M.GAPX and bhi + M.GAPX >= bx0:
                bx0 = min(bx0, blo); bx1 = max(bx1, bhi); by1 = y
                bcore += c_cnt
                if c_cnt:
                    if not c_any:
                        cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
                        c_any = True
                    else:
                        cx0 = min(cx0, c_lo); cx1 = max(cx1, c_hi)
                        cy0 = min(cy0, y); cy1 = max(cy1, y)
            else:
                bands.append(M._pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any))
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt
                c_any = c_cnt > 0
                if c_any:
                    cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            last = y
        else:
            if active and (y - last) > M.VGAP:
                bands.append(M._pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any))
                active = False
    if active:
        bands.append(M._pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any))
    bands.sort(key=lambda b: -b["core"])
    return bands


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    for name, fn in SCENES:
        if only and only not in name:
            continue
        path = os.path.join(OUT, fn)
        if not os.path.exists(path):
            continue
        disp = np.asarray(Image.open(path).convert("RGB").resize((1280, 720), Image.BILINEAR))
        raw = M.disp_to_raw(disp)
        print("=" * 104)
        print("场景 %s (%s)   网格 160x90" % (name, fn))
        print("=" * 104)

        # 掩码统计
        s = raw.astype(np.int32)[::M.DS, ::M.DS, :]
        m = M.classify(s)
        for k in ("orange", "yg", "dark"):
            hh, cc = m[k]
            print("  %-8s halo %6d 格 (%5.2f%%)   core %6d 格 (%5.2f%%)"
                  % (CLS_CN[k], int(hh.sum()), 100.0 * hh.sum() / hh.size,
                     int(cc.sum()), 100.0 * cc.sum() / cc.size))

        bl = band_list(raw)
        for k in ("orange", "yg", "dark"):
            print("  --- %s 的 band（按 core 数排序，最多 6 个）---" % CLS_CN[k])
            bs = bl[k][:6]
            if not bs:
                print("      无 band")
                continue
            for b in bs:
                hb = b["halo_box"]
                cb = b["core_box"]
                area = 0.0
                if cb:
                    area = 100.0 * (cb[1] - cb[0] + 1) * (cb[3] - cb[2] + 1) / (M.W * M.H)
                cs = b["core_solid"]
                print("      core数=%6d 密实度=%.3f  core框=(%3d,%3d)-(%3d,%3d) w=%3d h=%3d 占画面%5.1f%%"
                      "  halo框=(%3d,%3d)-(%3d,%3d)"
                      % (b["core"], cs, cb[0] if cb else -1, cb[2] if cb else -1,
                         cb[1] if cb else -1, cb[3] if cb else -1,
                         b.get("core_w", 0), b.get("core_h", 0), area,
                         hb[0], hb[2], hb[1], hb[3]))
        print()


if __name__ == "__main__":
    main()
