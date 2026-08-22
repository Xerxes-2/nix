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

  time.timeZone = "Australia/Melbourne";
}
