#!/usr/bin/env bash
# 本机跑：在 Mac mini 上用 peek.py 改一组寄存器，测 UDP 发送吞吐和每包重传，再恢复。
#   try.sh <标签> [addr=val ...]      例：try.sh aifsn1 0x69c=1
# 需要：机器上 /tmp/peek.py、iperf-srv 已在 Wi‑Fi 地址上跑、Wi‑Fi 驱动是 b43。
set -eu
H=${H:-xerxes2@192.168.68.104}
W=${W:-192.168.68.112}
IPERF=${IPERF:-/nix/store/700nv9776ddw5fnksbf50fqvrv3cz5xp-iperf-3.21/bin/iperf3}
O="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=8"
label=$1
shift
remote() { ssh $O "$H" "sudo bash -c '$1'"; }
st() { remote "iw dev wlp3s0b1 station dump | awk \"/tx packets|tx retries/{print \\\$3}\" | paste -sd\" \""; }
saved=()
for kv in "$@"; do
  a=${kv%%=*}
  old=$(remote "python3 /tmp/peek.py r16 $a" | cut -d= -f2)
  saved+=("$a=$old")
  remote "python3 /tmp/peek.py w16 $a ${kv#*=}" >/dev/null
done
now=$(remote "python3 /tmp/peek.py r16 ${*%%=*} 2>/dev/null" 2>/dev/null || true)
# 重连会清掉 table 200 的路由，每次都补上，否则回包走有线、测出来是假数
remote "ip route replace 192.168.68.0/24 dev wlp3s0b1 src $W table 200; ip rule show | grep -q \"from $W lookup 200\" || ip rule add from $W table 200"
read -r p0 r0 <<<"$(st)"
tx=$($IPERF -c "$W" -t 5 -R -u -b 40M | awk '/receiver/{print $7}')
read -r p1 r1 <<<"$(st)"
after=$(remote "python3 /tmp/peek.py r16 ${*%%=*} 2>/dev/null" 2>/dev/null || true)
for kv in "${saved[@]}"; do remote "python3 /tmp/peek.py w16 ${kv%%=*} ${kv#*=}" >/dev/null; done
# 发出的包数应约等于 40Mbit/s*5s/1470B≈17000；远小于说明没走 Wi‑Fi 或链路死了
awk -v l="$label" -v t="$tx" -v p=$((p1 - p0)) -v r=$((r1 - r0)) -v n="$now" -v a="$after" \
  'BEGIN{printf "%-14s tx %5s Mbit/s  retry/pkt %.2f  pkts %6d | set: %s | after: %s\n", l, t, (p ? r / p : 0), p, n, a}'
