# ===== 网络 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  networking.hostName = "instance-20260821-1942";
  # useNetworkd / useDHCP 在 modules/oci-guest.nix（OCI 的 DHCP 下发 IP/路由/MTU）
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ]; # 其余服务走 cloudflared 隧道

  # tailscale：给不应该进公网隧道的东西一条路，兼作 22 不通时的第二条管理通道
  # （第三条是 OCI 控制台串口）。cloudflared 面向公开服务。
  # 当初引入它的直接理由是 Ignition 演示网关，那个 2026-09 已迁往 a1；这里保留
  # 是因为管理通道本身值得保留，不是忘了删。服务的端口规则跟着各自的模块走。
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641：直连打洞；没有它会退化成经 DERP 中继
  };

  time.timeZone = "Australia/Melbourne";
}
