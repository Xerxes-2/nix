# 扫描期间每 20 ms ping 一次网关，报告扫描时长和丢包
I=$(ls /sys/class/ieee80211/*/device/net/ | head -1); GW=192.168.68.1
for n in 1 2 3; do
  ping -D -i 0.02 -W 0.5 -I $I $GW > /tmp/sp.txt 2>&1 & p=$!
  sleep 1; t0=$(date +%s.%N); iw dev $I scan >/dev/null 2>&1; t1=$(date +%s.%N); sleep 1; kill -INT $p; wait $p 2>/dev/null
  echo "$t0 $t1 $(grep -c 'bytes from' /tmp/sp.txt) $(tail -2 /tmp/sp.txt | head -1)" | awk '{printf "扫描 %.1fs  ", $2-$1; $1=$2=$3=""; print}'
done
