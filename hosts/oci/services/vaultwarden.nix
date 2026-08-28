# ===== vaultwarden 密码库 =====
{ config, ... }:
{
  # vaultwarden（Bitwarden 兼容服务端），sqlite，仅监听本机，
  # 经 cloudflared 隧道暴露为 https://vault.xerxes2.com
  # （Cloudflare dashboard 里的 public hostname → http://localhost:8222）。
  # ADMIN_TOKEN 放 sops vaultwarden-env（argon2 哈希，`vaultwarden hash` 生成）。
  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    # 模块自带 sqlite .backup 的每日备份（23:00），比 restic 直接抄
    # 运行中的 db.sqlite3 可靠；restic 03:00 备的是这个目录。
    backupDir = "/var/backup/vaultwarden";
    environmentFile = config.sops.secrets."vaultwarden-env".path;
    config = {
      DOMAIN = "https://vault.xerxes2.com";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      # 公网可达，注册永久关闭；开新账号走 /admin 面板邀请
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = true;
    };
  };
}
