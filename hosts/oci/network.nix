# ===== 网络 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  networking.hostName = "instance-20260821-1942";
  networking.useNetworkd = true;
  networking.useDHCP = true; # OCI DHCP 下发 IP/路由/MTU
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ]; # 其余服务走 cloudflared 隧道

  # tailscale：给那些不应该进公网隧道的东西一条路。cloudflared 面向公开
  # 服务；Ignition 网关（services/ignition.nix）带管理员入口和设备写入能力，
  # 只在 tailnet 内可达。端口规则跟着各自的服务模块走。
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641：直连打洞；没有它会退化成经 DERP 中继
  };

  time.timeZone = "Australia/Melbourne";
}
