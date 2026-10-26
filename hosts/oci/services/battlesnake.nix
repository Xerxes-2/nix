# ===== battlesnake（自己的 Battlesnake 蛇，F#）=====
{ inputs, ... }:
{
  imports = [ inputs.battlesnake.nixosModules.default ];

  # 无状态 HTTP 服务：Battlesnake 引擎（GCP us-west1）每回合 POST /move，回一个方向，
  # 超时 500ms 含网络。
  #
  # 直连公网 http://152.67.123.41:8100，**不走 cloudflared 隧道**：免费套餐的请求会被
  # Cloudflare 内部转到 LHR/AMS/BOS 这些远处机房处理（CF-RAY 可见），再进悉尼的隧道，
  # 实测 cfOrigin 640–1000ms，整回合超时。直连 us-west1 → oci ping 约 165ms。
  # 纯 HTTP 不上 TLS：没有状态和秘密可保护，TLS 握手却要多付跨太平洋往返。
  # 隧道的 https://snake.xerxes2.com（→ localhost:8100，不套 Access）留着给自己 curl 调试。
  #
  # 除了这里的 NixOS 防火墙，Oracle 控制台 VCN 的 security list 也要放行 TCP 8100。
  services.battlesnake = {
    enable = true;
    host = "0.0.0.0";
    # 8000 被 SillyTavern 占了
    port = 8100;
    openFirewall = true;
  };

  # 0.7.3 起程序默认把 Standard 天梯局按 game id 奇偶分成新旧两组对照。4 天约 450 局，
  # 两组名次差在噪声内（z≈1.2），说明多线程和 0.6.1 的放宽重搜都不是掉分原因，全员用新配置。
  systemd.services.battlesnake.environment.SNAKE_AB = "0";
}
