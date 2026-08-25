# ===== wakapi 原生服务 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # wakapi 原生服务（从 rootless 容器迁入，2026-08）。DynamicUser，
  # 数据在 /var/lib/private/wakapi/wakapi.db（/var/lib/wakapi 是 symlink）。
  # salt 必须与容器时代一致（密码哈希依赖它）：sops wakapi-env
  services.wakapi = {
    enable = true;
    environmentFiles = [ config.sops.secrets."wakapi-env".path ];
    settings = {
      server = {
        listen_ipv4 = "127.0.0.1";
        port = 3000;
        public_url = "https://waka.xerxes2.com";
      };
      db = {
        dialect = "sqlite3";
        name = "wakapi.db"; # 相对 WorkingDirectory=/var/lib/wakapi
      };
      app = {
        leaderboard_enabled = true;
        leaderboard_require_auth = true;
      };
      security = {
        insecure_cookies = false;
        allow_signup = false;
        invite_codes = true;
        disable_frontpage = true;
      };
    };
  };
}
