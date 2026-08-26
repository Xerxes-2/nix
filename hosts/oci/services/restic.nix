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
  # 仓库 URL 也放进 restic-env（RESTIC_REPOSITORY=s3:https://<ns>.compat.objectstorage.<region>.oraclecloud.com/<bucket>），
  # 避免 tenancy namespace / bucket 名进公开 git。environmentFile 已设时模块断言允许 repository 留空。
  services.restic.backups.oci = {
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
      # host key 能解密 secrets/oci.yaml（密文在公开 repo 里），不要进备份
      "/etc/ssh/ssh_host_*_key"
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
