#!/usr/bin/env python3
"""比较两份 decode.py 输出在某个阶段标记处的硬件状态（PHY / 射频 / PHY 表）。

用法: regdiff.py wl.txt b43.txt [PHASE]     （默认 linked）
      文件名可写成 文件@行号：取到该行为止的状态（同一份 trace 的两个时刻也能比，如 20/40 MHz 切换前后）

状态 = 到该标记为止每个地址最后一次读到或写入的值。MMIO 按 BAR0 偏移，SHM 按 routing:字节偏移。PHY 表按 b43 的
tables_phy_ht.c 语义还原：写 0x072 设地址（表号<<10 | 偏移），写 0x074 暂存高 16 位，
读写 0x073 完成一次访问并让地址自增。计数器、状态类寄存器会混进噪声，需人工筛。
"""

import re
import sys

TADDR, TLO, THI = 0x072, 0x073, 0x074
LINE = re.compile(r"(PHY|RADIO) ([RW]) 0x([0-9a-f]+) (?:=|->) 0x([0-9a-f]+)")
MMIO = re.compile(r"MMIO ([RW]) w(\d) \+0x([0-9a-f]+) (?:=|->) 0x([0-9a-f]+)")
SHM = re.compile(r"SHM ([RW]) r(\d+):0x([0-9a-f]+)(\+hi)? w\d (?:=|->) 0x([0-9a-f]+)")


def snapshot(path, phase):
    st = {}
    ptr, hi = None, None
    path, _, stop = path.partition("@")
    for n, line in enumerate(open(path), 1):
        if stop and n > int(stop):
            break
        if line.startswith("== "):
            if stop:
                continue
            if line.split()[-1] == phase:
                break
            continue
        m = SHM.match(line)
        if m:
            st[("SHM", int(m.group(2)), int(m.group(3), 16) * 2 + (2 if m.group(4) else 0))] = int(m.group(5), 16)
            continue
        m = MMIO.match(line)
        if m:
            st[("MMIO", int(m.group(3), 16))] = int(m.group(4), 16)
            continue
        m = LINE.match(line)
        if not m:
            continue
        kind, op, a, v = m.group(1), m.group(2), int(m.group(3), 16), int(m.group(4), 16)
        if kind == "PHY" and a == TADDR and op == "W":
            ptr, hi = v, None
        elif kind == "PHY" and a == THI:
            hi = v
        elif kind == "PHY" and a == TLO and ptr is not None:
            val = v if hi is None else (hi << 16) | v
            st[("TAB", ptr >> 10, ptr & 0x3FF)] = val
            ptr, hi = ptr + 1, None
        else:
            st[(kind, a)] = v
    return st


def key_str(k):
    if k[0] == "TAB":
        return f"TAB {k[1]:3d}[{k[2]:3d}]"
    if k[0] == "SHM":
        return f"SHM r{k[1]}:0x{k[2]:04x}"
    return f"{k[0]:5s} 0x{k[1]:04x}"


def main():
    phase = sys.argv[3] if len(sys.argv) > 3 else "linked"
    a, b = snapshot(sys.argv[1], phase), snapshot(sys.argv[2], phase)
    only_a = sorted(k for k in a if k not in b)
    diff = sorted(k for k in a if k in b and a[k] != b[k])
    print(f"# {len(a)} vs {len(b)} 个地址；值不同 {len(diff)}，只有前者碰过 {len(only_a)}")
    print("## 值不同（前者 / 后者）")
    for k in diff:
        print(f"{key_str(k)}  0x{a[k]:x} / 0x{b[k]:x}")
    print("## 只有前者碰过")
    for k in only_a:
        print(f"{key_str(k)}  0x{a[k]:x}")


if __name__ == "__main__":
    main()
