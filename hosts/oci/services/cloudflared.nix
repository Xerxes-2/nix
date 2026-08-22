# ===== cloudflared 隧道 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # cloudflared tunnel（token 方式）。
  # token：sops cloudflared-env（TUNNEL_TOKEN=...）。
  systemd.services.cloudflared = {
    description = "cloudflared tunnel";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      TimeoutStartSec = 15;
      EnvironmentFile = config.sops.secrets."cloudflared-env".path;
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate tunnel run";
      Restart = "on-failure";
      RestartSec = "5s";
      DynamicUser = true;
    };
  };
}
