# TCP tuning for long, lossy intercontinental paths.
#
# Everything this machine talks to inside Australia is 2-15ms away and needs
# none of this. Bilibili does: the video/live edges it hands out are a mixed
# bag, and losing the lottery means a ~200-260ms RTT path with real loss and
# heavy reordering. Measured on one live stream (`ss -ti`, edge
# d1--ov-gotcha207.bilivideo.com / 38.60.148.100):
#
#   rtt:222ms  cwnd:10  rcv_ooopack:91099 of 245105 segments (~37% reordered)
#   bytes_retrans:1214  delivery_rate 149kbps
#
# versus a well-placed edge at the same moment (mirrorcosov / 92.223.78.30):
# rtt 20ms, zero reordering, 3.5Mbps. cubic reads that reordering as
# congestion and never lets the window leave the initial 10 segments, which
# is far below the ~500KB bandwidth-delay product such a path needs, so the
# player's buffer drains and playback stalls.
{ ... }:
{
  boot.kernelModules = [ "tcp_bbr" ];

  boot.kernel.sysctl = {
    # BBR estimates bandwidth and RTT instead of treating every lost or
    # reordered packet as congestion, which is the whole problem above. Same
    # reasoning as hosts/oci/boot.nix, different direction of traffic.
    "net.ipv4.tcp_congestion_control" = "bbr";

    # BBR paces its sends; without a pacing-capable qdisc that falls back to
    # the kernel's internal pacing, which is coarser. Only affects devices
    # created after boot - wlan0 comes up under mac80211's own fq_codel and
    # is fine either way.
    "net.core.default_qdisc" = "fq";

    # Some transpacific paths are PMTU black holes: the ICMP "too big" never
    # comes back and the connection just hangs on a full-size segment. Let
    # TCP probe its way down instead. (Confirmed the local path is clean at
    # 1500, so this only ever arms itself further out.)
    "net.ipv4.tcp_mtu_probing" = 1;

    # Autotuning caps the receive window at tcp_rmem's third field. 260ms at
    # 20Mbps is a ~650KB BDP and the stock 6MB ceiling already covers it, but
    # rmem_max was the smaller 4MB and applies to anything calling
    # SO_RCVBUF explicitly. Raise both so nothing is window-limited.
    "net.core.rmem_max" = 33554432;
    "net.ipv4.tcp_rmem" = "4096 262144 33554432";
  };
}
