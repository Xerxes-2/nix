#!/usr/bin/env bash
# 在本机（x86 工作站）跑：经 Mac mini 的 Wi‑Fi 地址测两个方向的吞吐和 ping。
#   bench.sh <wifi-ip> [MiB]
set -eu
W=xerxes2@$1
N=${2:-40}
O="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=8"
mbit() { awk -v n="$N" -v t="$1" 'BEGIN{printf "%.1f", n*8*1.048576/t}'; }
ping -q -c 50 -i 0.2 "$1" | tail -2 | tr '\n' ' '
echo
t0=$(date +%s.%N); ssh $O "$W" "head -c ${N}M /dev/zero" >/dev/null; t1=$(date +%s.%N)
echo "TX(mini->) $(mbit "$(echo "$t1 - $t0" | bc)") Mbit/s"
t0=$(date +%s.%N); head -c ${N}M /dev/zero | ssh $O "$W" 'cat >/dev/null'; t1=$(date +%s.%N)
echo "RX(->mini) $(mbit "$(echo "$t1 - $t0" | bc)") Mbit/s"
ssh $O "$W" bash -s <<'R'
IF=$(ls /sys/class/net | grep ^wl | head -1)
iw dev $IF station dump | grep -E "tx (packets|retries|failed)|bitrate|signal:" | tr -s '\t ' ' ' | paste -sd' '
R
