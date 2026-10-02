#!/usr/bin/env python3
"""经 /dev/mem 读写 BCM4331 BAR0（D11 核心窗口），不经过驱动。wl 运行时也能用。

需要内核参数 iomem=relaxed（mmiotrace 启动项里有）。BAR0 窗口切核靠 PCI 配置
空间 0x80，这里不动它，读到的是驱动当前选中的核心（正常就是 D11）。

  peek.py r16 0x688 [0x69c ...]        读 16 位
  peek.py w16 0x688 0x1f07             写 16 位（危险，只在实验时用）
  peek.py ifs                          打印 IFS 寄存器组：遍历 IFSCTL 选择器 0..3 读 0x680-0x69e，
                                       最后恢复原值
  peek.py banks                        选择器 0..3 各读一遍 0x680/682/684/69c，恢复原选择器
  peek.py wlinit [aifsn]               照 wl 的顺序给四个槽写 AIFSN（默认 2），恢复原选择器
  peek.py phyr 0x424 [...]             经 0x3fc/0x3fe 间接读 PHY 寄存器
  peek.py phyw 0x424 0x158 [...]       间接写 PHY 寄存器（与驱动竞争，实验用）
  peek.py tabr 27 0 64                 读 PHY 表（16 位，与驱动竞争）
  peek.py dump > x.txt                 扫全部 PHY/射频寄存器
  peek.py rate [addr] [n]              计数器每秒增量（每 50 ms 采一次，处理 16 位回绕）
  peek.py watch 0x692 [秒]             每 0.1 s 读一次，看计数器怎么跑
"""

import mmap
import os
import struct
import sys
import time

BAR0 = int(os.environ.get("BAR0", "0xa0600000"), 16)
SIZE = 0x4000
IFS = [0x680, 0x682, 0x684, 0x686, 0x688, 0x68A, 0x68C, 0x68E, 0x690,
       0x692, 0x694, 0x696, 0x698, 0x69A, 0x69C, 0x69E]


def open_bar():
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    return mmap.mmap(fd, SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BAR0)


def r16(m, a):
    return struct.unpack_from("<H", m, a)[0]


def w16(m, a, v):
    struct.pack_into("<H", m, a, v)


def main():
    m = open_bar()
    cmd, args = sys.argv[1], [int(x, 0) for x in sys.argv[2:]]
    if cmd == "r16":
        print(" ".join(f"0x{a:03x}=0x{r16(m, a):04x}" for a in args))
    elif cmd == "w16":
        w16(m, args[0], args[1])
        print(f"0x{args[0]:03x}=0x{r16(m, args[0]):04x}")
    elif cmd == "ifs":
        orig = r16(m, 0x688)
        print("sel    " + " ".join(f"{a:03x} " for a in IFS))
        for sel in range(4):
            w16(m, 0x688, (orig & ~0x3000) | (sel << 12))
            print(f"{sel}      " + " ".join(f"{r16(m, a):04x}" for a in IFS))
        w16(m, 0x688, orig)
        print(f"restored 0x688=0x{r16(m, 0x688):04x}")
    elif cmd == "banks":
        orig = r16(m, 0x688)
        for sel in range(4):
            w16(m, 0x688, (orig & ~0x3000) | (sel << 12))
            print(sel, " ".join(f"{a:03x}={r16(m, a):04x}" for a in (0x680, 0x682, 0x684, 0x69C)))
        w16(m, 0x688, orig)
    elif cmd == "wlinit":
        aifsn = args[0] if args else 2
        orig = r16(m, 0x688)
        for sel in range(4):
            w16(m, 0x688, (orig & ~0x3000) | (sel << 12))
            w16(m, 0x69C, aifsn)
        w16(m, 0x688, orig)
        print(f"0x688=0x{r16(m, 0x688):04x} 0x69c=0x{r16(m, 0x69C):04x}")
    elif cmd == "phyr":
        out = []
        for a in args:
            w16(m, 0x3FC, a)
            out.append(f"p{a:03x}=0x{r16(m, 0x3FE):04x}")
        print(" ".join(out))
    elif cmd == "phyw":
        # phyw addr val [addr val ...]；与驱动自己的 PHY 访问有竞争，只在实验时用
        for a, v in zip(args[::2], args[1::2]):
            w16(m, 0x3FC, a)
            w16(m, 0x3FE, v)
        print("ok")
    elif cmd == "tabr":
        # tabr 表号 偏移 个数：经 0x72/0x73 读 16 位表项（读 0x73 后偏移自增）
        t, off, n = args[0], args[1], (args[2] if len(args) > 2 else 1)
        w16(m, 0x3FC, 0x72)
        w16(m, 0x3FE, (t << 10) | off)
        out = []
        for _ in range(n):
            w16(m, 0x3FC, 0x73)
            out.append(r16(m, 0x3FE))
        print(" ".join(f"{v:04x}" for v in out))
    elif cmd == "dump":
        # 整段扫 PHY（0x000–0xfff）和射频（0x000–0xfff），跳过有副作用的表访问端口
        skip = {0x72, 0x73, 0x74}
        for a in range(0x1000):
            if a in skip:
                continue
            w16(m, 0x3FC, a)
            print(f"PHY {a:04x} {r16(m, 0x3FE):04x}")
        for a in range(0x1000):
            w16(m, 0x3D8, a | 0x200)
            print(f"RADIO {a:04x} {r16(m, 0x3DA):04x}")
    elif cmd == "rate":
        # 16 位计数器的每秒增量（处理回绕），默认 0x692 信道忙
        a = args[0] if args else 0x692
        n = args[1] if len(args) > 1 else 20
        tot, prev = 0, r16(m, a)
        for _ in range(n):
            time.sleep(0.05)
            cur = r16(m, a)
            tot += (cur - prev) & 0xFFFF
            prev = cur
        print(f"0x{a:03x} +{tot / (n * 0.05):.0f}/s")
    elif cmd == "watch":
        a, secs = args[0], (args[1] if len(args) > 1 else 2)
        for _ in range(int(secs * 10)):
            print(f"0x{r16(m, a):04x}", end=" ", flush=True)
            time.sleep(0.1)
        print()


if __name__ == "__main__":
    main()
