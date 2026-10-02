#!/usr/bin/env bash
# 工作站侧：每秒 ping 一次 Mac mini 的 Wi‑Fi 地址；每 10 分钟各方向 30 秒 TCP
. ~/Dev/nix/hosts/macmini/b43-ht/air.sh
L=~/Dev/b43-re/soak-ws.log
ping -D -i 1 -W 1 $W > ~/Dev/b43-re/soak-ping.log 2>&1 &
while :; do
  sleep 600
  a=$($P -c $W -t 30 2>/dev/null | awk '/receiver/{print $7}'); b=$($P -c $W -t 30 -R 2>/dev/null | awk '/receiver/{print $7}')
  echo "$(date +%T) TCP收 ${a:-FAIL} TCP发 ${b:-FAIL}" >> $L
done
