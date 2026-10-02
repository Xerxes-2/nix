#!/usr/bin/env bash
# 每分钟一行：时间 频率/带宽 信号 发/收速率 PHY错误累计 下溢 txphyerr 可用内存 slab 重启次数 rekey次数
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
I=wlp3s0b1; L=/var/lib/b43-re/soak.log
while :; do
  D=$(ls -d /sys/kernel/debug/b43/phy* 2>/dev/null | head -1)
  link=$(iw dev $I link 2>/dev/null | awk '/freq/{f=$2} /signal/{s=$2} /tx bitrate/{t=$3" "$NF} /rx bitrate/{r=$3" "$NF} END{printf "%s %s tx=%s rx=%s", f, s, t, r}')
  w=$(iw dev $I info 2>/dev/null | grep -o 'width: [0-9]*' | cut -d' ' -f2)
  ms=$(bash /tmp/macstat.sh 2>/dev/null | awk '{printf "funfl=%d phyerr=%d", strtonum($8), strtonum($16)}')
  echo "$(date +%T) w=$w $link phyerrlog=$(dmesg | grep -c 'PHY transmission error') $ms mem=$(awk '/MemAvailable/{print $2}' /proc/meminfo) slab=$(awk '/^Slab/{print $2}' /proc/meminfo) restarts=$(dmesg | grep -c 'Controller RESET') rekey=$(journalctl -b -t wpa_supplicant --since -1min | grep -c 'Group rekeying') disc=$(journalctl -b -t wpa_supplicant --since -1min | grep -c 'CTRL-EVENT-DISCONNECTED')" >> $L
  sleep 60
done
