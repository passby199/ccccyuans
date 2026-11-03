# -*- coding: utf-8 -*-
"""
把 target_detect / pose_detect / target_osd 三个模块并入 param_ctrl.v。

为什么这么做
---------------------------------------------------------------------------
TD 只在【打开工程】时读 .al 清单，而且保存/关闭时会把内存里的清单写回 .al，
所以"外部改 .al 加新文件"这条路在 TD 开着的时候会被静默覆盖，
编译就报 `xxx is a black box`（2026-10-28 实测，文件数 66 -> 63）。

工程里的老规矩（交接文档 10.1 / sport_mode 的注释）就是：
**新模块塞进已登记的文件里** —— TD 每次编译都会重读文件内容，
所以不需要动 .al、不需要重启，直接就能综合到。

原来那 3 个独立 .v 不删，只把内容替换成一句指路注释（空文件编译无害），
这样无论 TD 内存里是 63 个还是 66 个文件，都能编译通过。
"""

import os
import shutil

HDL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # tools 的上一级
HOST = os.path.join(HDL, "param_ctrl.v")

MODS = ["target_detect.v", "pose_detect.v", "target_osd.v"]

BANNER = """

//=============================================================================
//=============================================================================
//
//  ⚠⚠ 下面 3 个模块（target_detect / pose_detect / target_osd）
//      原本是独立文件，2026-10-28 晚**合并到本文件**。
//
//  为什么合并
//  ---------------------------------------------------------------------------
//  TD 只在【打开工程】时读 camera_to_dsi_display.al 的文件清单，而且
//  **保存/关闭工程时会把内存里的清单写回 .al**。所以"在外部改 .al 加新文件"
//  这条路，只要 TD 还开着就会被静默覆盖，编译报：
//      ERROR: target_detect(...) is a black box in .../design_top_wrapper.v(1131)
//  （2026-10-28 实测：加了 3 条记录，编译时 .al 从 66 条变回 63 条。）
//
//  解决办法就是本工程一直用的办法：**把新模块塞进已登记的文件里**。
//  TD 每次编译都会重读文件【内容】，所以不需要动 .al、不需要 Add Source、
//  不需要重启，直接就能综合到。（sport_mode 当初也是这么处理的。）
//
//  以后新建模块也照这个来：小于 300 行的模块直接追加到本文件末尾。
//
//=============================================================================
//=============================================================================
"""


def strip_leading_header(text):
    """去掉文件开头那一段 //==== 的说明（保留正文），避免注释重复太多"""
    lines = text.split("\n")
    # 找到第一个 module 行
    for i, ln in enumerate(lines):
        if ln.startswith("module "):
            return i, "\n".join(lines[i:])
    return 0, text


def main():
    body = []
    for m in MODS:
        p = os.path.join(HDL, m)
        txt = open(p, encoding="utf-8").read()
        idx, core = strip_leading_header(txt)
        body.append("\n//---------------------------------------------------------------------------\n"
                    "//  来自原 %s（%d 行）\n"
                    "//---------------------------------------------------------------------------\n%s"
                    % (m, len(txt.split("\n")), core.rstrip()))

    merged = BANNER + "\n".join(body) + "\n"

    host = open(HOST, encoding="utf-8").read()
    if "module target_detect" in host:
        print("param_ctrl.v 里已经有 target_detect 了，跳过合并")
    else:
        shutil.copy(HOST, HOST + ".bak_before_merge")
        open(HOST, "a", encoding="utf-8").write(merged)
        print("已合并到 param_ctrl.v，现在 %d 行" % len(open(HOST, encoding="utf-8").read().split("\n")))

    # 把 3 个独立文件清空成指路注释
    stub = """//=============================================================================
//  %s  --  【已合并到 param_ctrl.v，本文件留空】
//
//  2026-10-28 晚：为了绕开 TD 的 "black box"（.al 清单会被 TD 覆盖），
//  本模块的代码已经并入 param_ctrl.v 的末尾。
//
//  ⚠ 不要再往这里加代码，否则会出现"模块重复定义"。
//  ⚠ 本文件保留在工程清单里也无害（空文件），删掉它反而可能让 TD 报找不到文件。
//=============================================================================
"""
    for m in MODS:
        p = os.path.join(HDL, m)
        if "module " in open(p, encoding="utf-8").read():
            open(p, "w", encoding="utf-8").write(stub % m)
            print("已清空 %s" % m)


if __name__ == "__main__":
    main()
