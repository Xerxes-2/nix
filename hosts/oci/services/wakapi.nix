# ===== wakapi 原生服务 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # 临时 overlay：wakapi 2.17.6（schema 必须 >= 2.17.6，容器时代的 :latest 已跑过
  # 20260722_sqlite_convert_time_to_integer 迁移，2.17.5 无法读该 schema）。
  # hash 拄自 nixpkgs master pkgs/by-name/wa/wakapi/package.nix。
  # TODO: nixos-unstable channel 的 wakapi >= 2.17.6 后删除此 overlay。
  nixpkgs.overlays = [
    (final: prev: {
      wakapi = prev.wakapi.overrideAttrs (old: rec {
        version = "2.17.6";
        src = prev.fetchFromGitHub {
          owner = "muety";
          repo = "wakapi";
          tag = version;
          hash = "sha256-fKCfjLh/nf6rRqxdGPWfEY9EDh+5sXSKkvzgq7D4ocE=";
        };
        vendorHash = "sha256-eyldhpDU5fT7tHdsQZ4qUrPlu1QSYaXX8FgksvAXiOw=";
        # 2.17.6 的个别路由测试在非 buildGoLatestModule 环境下失败，临时跳过
        doCheck = false;
      });
    })
  ];

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
