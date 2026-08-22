# ===== restic 异地备份 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # restic 每日异地备份→ OCI Object Storage（复用 Ubuntu 时代的 vps-backup 仓库）。
  # 旧快照 host=OCI-Ubuntu-arm，新的 host=oci；forget 按 paths 分组，
  # 路径集不变故旧快照会随保留策略自然淘汰。
  # 凭据：sops restic-password / restic-env。
  services.restic.backups.oci = {
    repository = "s3:https://REDACTED.compat.objectstorage.ap-sydney-1.oraclecloud.com/vps-backup";
    passwordFile = config.sops.secrets."restic-password".path;
    environmentFile = config.sops.secrets."restic-env".path;
    paths = [
      "/home/ubuntu/dufs-data"
      "/var/lib/private/wakapi"
      "/var/lib/SillyTavern"
      "/home/ubuntu/.config"
      "/etc"
    ];
    exclude = [
      "**/.cache"
      "**/node_modules"
      "**/__pycache__"
      "*.swp"
      "*.tmp"
    ];
    extraBackupArgs = [
      "--exclude-caches"
      "--tag"
      "scheduled"
      "--host"
      "oci"
    ];
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
      "--group-by paths"
    ];
    timerConfig = {
      OnCalendar = "03:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };
}
