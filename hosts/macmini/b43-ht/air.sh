# 空口测量辅助函数，在工作站上 source（bash）。
# 前提：工作站走有线上网，Mac mini 的有线口直连工作站（链路本地地址登录），
# 工作站的无线网卡空出来做监听；mon_on/mon_off 需要对 iw、ip 免密 sudo。
#   . air.sh; mon_on; sig 标签 [秒]; mon_off
O="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=8"
M='xerxes2@fe80::ca2a:14ff:fe55:20c5%enp10s0'
P=/nix/store/700nv9776ddw5fnksbf50fqvrv3cz5xp-iperf-3.21/bin/iperf3
W=192.168.68.112; MAC=28:cf:da:02:ff:39
mon_on(){ nmcli dev disconnect wlan0 >/dev/null 2>&1; sudo -n ip link set wlan0 down; sudo -n iw dev wlan0 set type monitor; sudo -n ip link set wlan0 up; sudo -n iw dev wlan0 set freq ${1:-5220 HT20}; }  # 参数如 "2457 HT20"；80 MHz 监听几乎解不出我们 20 MHz 的 HT 帧
mon_off(){ sudo -n ip link set wlan0 down; sudo -n iw dev wlan0 set type managed; sudo -n ip link set wlan0 up; sleep 3; nmcli dev wifi rescan >/dev/null 2>&1; sleep 4; nmcli con up DECO ifname wlan0 >/dev/null; }
# 抓 Mac mini 发出的帧：信号强度中位数、解出的数据帧数、路由器回的 ACK 数
sig(){ timeout $((${2:-3}+2)) tcpdump -i wlan0 -s 120 -w /tmp/sig.pcap "wlan addr1 $MAC or wlan addr2 $MAC" 2>/dev/null & sleep 1
  x=$($P -c $W -t ${2:-3} -R -u -b 60M | awk '/receiver/{print $7}'); wait
  d=$(tshark -r /tmp/sig.pcap -Y "wlan.ta==$MAC && wlan.fc.type==2" -T fields -e radiotap.dbm_antsignal 2>/dev/null | sort -n)
  a=$(tshark -r /tmp/sig.pcap -Y "wlan.ra==$MAC && wlan.fc.type==1" 2>/dev/null | wc -l)
  n=$(echo "$d" | grep -c .); med=$(echo "$d" | sed -n "$(( (n+1)/2 ))p")
  echo "$1: ${x} Mbit/s  数据帧 $n  信号中位 ${med} dBm  ACK $a"; }
