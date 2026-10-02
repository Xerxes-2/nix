#!/usr/bin/env bash
# 在 Mac mini 上切 Wi‑Fi 驱动并连 DECO。要 root、要接网线（切换期间 Wi‑Fi 断）。
#   swap.sh b43 [htphy_5ghz] [band]   band: a=5GHz, bg=2.4GHz, 空=不锁
#   swap.sh wl [-] [band]
# 连上后给 Wi‑Fi 地址加策略路由（table 200），让从 Wi‑Fi 地址发出的包也走 Wi‑Fi，
# 否则同网段回包会走有线，测速不准。
set -eu
PCI=0000:03:00.0
CON=DECO

pci_reset() {
  rmmod b43 wl bcma 2>/dev/null || true
  echo 1 >/sys/bus/pci/devices/$PCI/remove
  sleep 2
  echo 1 >/sys/bus/pci/rescan
  sleep 3
  rmmod wl 2>/dev/null || true # rescan 会自动绑 wl
}

case "$1" in
b43)
  pci_reset
  modprobe bcma
  if [ -n "${B43KO:-}" ]; then modprobe mac80211; modprobe cordic; modprobe ssb 2>/dev/null || true; insmod "$B43KO" htphy_5ghz="${2:-0}" ${B43ARGS:-}; else modprobe b43 htphy_5ghz="${2:-0}" ${B43ARGS:-}; fi
  ;;
wl)
  pci_reset
  modprobe wl
  ;;
*)
  echo "usage: $0 b43 [0|1|2] [a|bg] | wl" >&2
  exit 2
  ;;
esac

sleep 6
IF=$(ls /sys/class/net | grep '^wl' | head -1)
nmcli dev set "$IF" managed yes
nmcli con modify $CON 802-11-wireless.band "${3:-}"
nmcli dev wifi rescan ifname "$IF" 2>/dev/null || true
sleep 6
nmcli -w 45 con up $CON ifname "$IF" >/dev/null
sleep 2
IP=$(ip -4 -br a show "$IF" | awk '{print $3}' | cut -d/ -f1)
NET=$(ip -4 route show dev "$IF" scope link | awk 'NR==1{print $1}')
ip rule del table 200 2>/dev/null || true
ip rule add from "$IP" table 200
ip route replace "$NET" dev "$IF" src "$IP" table 200
echo "$IF $IP $(iw dev "$IF" link | awk '/freq/{print $2"MHz"}')"
