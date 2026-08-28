# ===== ntfy 推送 + systemd 失败告警 =====
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # 告警统一发这个 topic；手机/桌面订阅它。
  topic = "oci-alerts";
  # 走 localhost 而不是 base-url：隧道挂掉时告警仍能落进 ntfy 的消息缓存，
  # 订阅端重连后靠 since= 补收。若走公网 URL，恰恰在最该报警时报不出去。
  publishUrl = "http://127.0.0.1:2586/${topic}";

  # 需要挂失败告警的单元。集中列在这里而不是散到各服务文件，
  # 是为了"覆盖了哪些"能一眼看全；新增服务时记得回来加一行。
  monitoredUnits = [
    "restic-backups-oci" # 异地备份失败 —— 最不能静默的一个
    "backup-vaultwarden" # 密码库 sqlite 快照，restic 备的就是它的产物
    "cloudflared" # 隧道断 = 所有对外服务不可达
    "vaultwarden"
    "wakapi"
    "sillytavern"
    "btrfs-scrub--" # 单元名由挂载点 "/" 转义而来（escapeSystemdPath）
    "snapper-timeline"
    "snapper-cleanup"
    "beesd@root"
    "nix-gc"
    "nix-optimise"
    "fail2ban"
    # 故意不含 ntfy-sh 自己：它挂了就没人能发这条告警，挂上去只是自欺。
    # 「整台机器失联」同理需要外部 dead-man's switch，见 README。
  ];
in
{
  # ntfy（推送通知服务端），仅监听本机，经 cloudflared 暴露为
  # https://ntfy.xerxes2.com（Cloudflare dashboard 里加 public hostname →
  # http://localhost:2586）。
  services.ntfy-sh = {
    enable = true;
    # 用户、ACL、令牌都走 environmentFile：模块把 settings 渲染成
    # /etc/ntfy/server.yml（全局可读），密码哈希和令牌不能进那里，也不能进 nix store。
    # sops ntfy-env：NTFY_AUTH_USERS / NTFY_AUTH_ACCESS / NTFY_AUTH_TOKENS。
    environmentFile = config.sops.secrets."ntfy-env".path;
    settings = {
      base-url = "https://ntfy.xerxes2.com";
      listen-http = "127.0.0.1:2586";
      # 只有 cloudflared 能连上来，限流要按 X-Forwarded-For 而不是隧道的回环地址
      behind-proxy = true;
      # 公网可达：默认拒绝一切匿名读写，没有这行就是一台任人发消息的公共中转
      auth-default-access = "deny-all";
      enable-signup = false;
      # admin 账号（角色 admin，全权，用来订阅）+ alerts 账号
      # （只对 oci-alerts 有 write-only，令牌泄露也读不到历史消息）都在 sops 里声明。
    };
  };

  systemd.services = lib.mkMerge [
    {
      # OnFailure= 拉起的模板单元：%i 是失败单元的全名（含 .service 后缀）。
      # 不设 wantedBy，只被动触发。
      "notify-failure@" = {
        description = "把 %i 的失败推送到 ntfy";
        scriptArgs = "%i";
        path = [
          pkgs.curl
          pkgs.systemd
        ];
        serviceConfig = {
          Type = "oneshot";
          # sops ntfy-token：NTFY_TOKEN=tk_…（alerts 账号的令牌，只写 oci-alerts）
          EnvironmentFile = config.sops.secrets."ntfy-token".path;
        };
        script = ''
          unit="$1"
          # status 对失败单元必然返回非零，别让它把这个脚本带崩
          body="$(systemctl status --full --lines=25 "$unit" 2>&1 || true)"
          # 标题只能是 ASCII：ntfy 的 Title 走 HTTP header，非 ASCII 需要额外编码；
          # 正文是 body，UTF-8 直接发没问题。
          curl -fsS --max-time 20 --retry 3 --retry-delay 5 \
            -H "Authorization: Bearer $NTFY_TOKEN" \
            -H "Title: systemd: $unit failed on oci" \
            -H "Priority: high" \
            -H "Tags: rotating_light" \
            -d "$body" \
            ${publishUrl}
        '';
      };
    }
    (lib.genAttrs monitoredUnits (_: {
      onFailure = [ "notify-failure@%n.service" ];
    }))
  ];
}
