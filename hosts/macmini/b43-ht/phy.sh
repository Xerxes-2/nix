#!/usr/bin/env bash
# 经 b43 debugfs 的 mmio16 接口间接读写 PHY/射频寄存器（不需要 iomem=relaxed）。
#   phy.sh r 0x1e7 0x222 ...      读 PHY
#   phy.sh w 0x1e7 0x20 ...       写 PHY（地址 值 成对）
#   phy.sh rr 0x159 ...           读射频（0x3d8/0x3da，读要或上 0x200）
#   phy.sh rw 0x159 0x11 ...      写射频
#   phy.sh tr 47 0x0 22 [32]       读 PHY 表（表号 偏移 个数 [位宽]）
# 与驱动自己的 PHY 访问有竞争，只在实验时用。
set -eu
D=$(ls -d /sys/kernel/debug/b43/phy* | head -1)
mw() { echo "$1 0x0 $2" > "$D/mmio16write"; }
# 只能一次 read()：debugfs 每次 read() 都真读硬件，cat 的第二次 read 会让表地址多自增一次
mr() { echo "$1" > "$D/mmio16read"; dd if="$D/mmio16read" bs=64 count=1 status=none; }
cmd=$1; shift
case $cmd in
r)  for a; do mw 0x3fc "$a"; printf "%s=%s " "$a" "$(mr 0x3fe)"; done; echo ;;
w)  while [ $# -ge 2 ]; do mw 0x3fc "$1"; mw 0x3fe "$2"; shift 2; done ;;
rr) for a; do mw 0x3d8 "$(printf 0x%x $((a | 0x200)))"; printf "%s=%s " "$a" "$(mr 0x3da)"; done; echo ;;
rw) while [ $# -ge 2 ]; do mw 0x3d8 "$1"; mw 0x3da "$2"; shift 2; done ;;
tr) t=$1 o=$2 n=$3 wd=${4:-16}
    mw 0x3fc 0x72; mw 0x3fe "$(printf 0x%x $(( (t << 10) | o )))"
    for _ in $(seq "$n"); do
        mw 0x3fc 0x73; lo=$(mr 0x3fe)
        if [ "$wd" = 32 ]; then mw 0x3fc 0x74; printf "%x " $(( ($(mr 0x3fe) << 16) | lo )); else printf "%x " $((lo)); fi
    done; echo ;;
esac
