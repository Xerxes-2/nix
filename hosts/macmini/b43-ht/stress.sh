#!/usr/bin/env bash
# 用法（Mac mini 上，root）：stress.sh reconnect|linkflap|restart|band|scan [次数]
# b43 稳定性压力：$1 = 测试名，$2 = 次数。每次记录恢复到能 ping 通网关的时间。
I=wlp3s0b1; GW=192.168.68.1; N=${2:-10}
B5=6a:5a:b0:97:24:e9; B2=66:5a:b0:97:24:e8
D=$(ls -d /sys/kernel/debug/b43/phy* 2>/dev/null | head -1)
up() { # 等到能 ping 通，返回秒数，60 秒失败
  local t0=$(date +%s.%N)
  for i in $(seq 600); do ping -c1 -W1 -I $I $GW >/dev/null 2>&1 && { echo "$(date +%s.%N) $t0" | awk '{printf "%.1f", $1-$2}'; return 0; }; sleep 0.1; done
  echo FAIL; return 1; }
freq() { iw dev $I link | awk '/freq/{printf "%s", $2} /signal/{printf "/%s", $2}'; }
bg_traffic() { ping -q -i 0.01 -s 1400 -I $I $GW >/dev/null 2>&1 & }
r=()
for n in $(seq $N); do
  case $1 in
    reconnect) nmcli con down DECO >/dev/null; nmcli con up DECO ifname $I >/dev/null 2>&1 & ;;
    linkflap)  bg_traffic; ip link set $I down; sleep 1; ip link set $I up ;;
    restart)   bg_traffic; echo 1 > $D/restart ;;
    band)      if [ $((n%2)) = 1 ]; then b=$B2; bd=bg; else b=$B5; bd=a; fi
               nmcli con modify DECO 802-11-wireless.bssid $b 802-11-wireless.band $bd
               nmcli con up DECO ifname $I >/dev/null 2>&1 & ;;
    scan)      bg_traffic; iw dev $I scan trigger >/dev/null 2>&1; sleep 4 ;;
  esac
  sleep 0.5; t=$(up); kill %1 %2 2>/dev/null; wait 2>/dev/null
  # NM 可能放弃了：拉回来再继续，别让一次失败拖垮后面所有轮
  [ "$t" = FAIL ] && { timeout 60 nmcli con up DECO ifname $I >/dev/null 2>&1; up >/dev/null; }
  r+=("$t@$(freq)"); case $t in 0.0|0.[0-9]|1.[0-9]) ;; *) echo "slow $t at $(cut -d" " -f1 /proc/uptime)";; esac
done
[ $1 = band ] && { nmcli con modify DECO 802-11-wireless.bssid "" 802-11-wireless.band a; nmcli con up DECO ifname $I >/dev/null 2>&1; }
echo "$1: ${r[*]}"
