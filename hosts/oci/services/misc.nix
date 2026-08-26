# ===== 其余系统服务与维护任务 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.openssh = {
    enable = true;
    # 只信任 /etc/ssh/authorized_keys.d/（即 users.users.*.openssh.authorizedKeys.keys）。
    # 默认还会读 ~/.ssh/authorized_keys，而那里残留的旧钥会静默绕过声明式配置
    # （迁移时写的兜底副本就造成过这个问题，2026-08 发现并清理）。
    authorizedKeysInHomedir = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # 22 端口对公网开放：封禁暴力扫描，减少日志噪音
  services.fail2ban.enable = true;

  # /var/log 独立子卷但无限额，防止日志无限增长
  services.journald.extraConfig = ''
    SystemMaxUse=500M
  '';

  # /home 时间线快照（容器数据全部 bind mount 在此）：误删/误改的兜底。
  # 保留策略克制：bees 的去重开销随快照数增长，快照也会钉住已删数据。
  # 首次启用前需手动：btrfs subvolume create /home/.snapshots
  services.snapper = {
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    configs.home = {
      SUBVOLUME = "/home";
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 6;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 0;
      TIMELINE_LIMIT_MONTHLY = 0;
      TIMELINE_LIMIT_YEARLY = 0;
    };
  };

  # 每月 scrub 检测静默数据损坏
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # OCI VCN 内部 NTP，低延迟且必达
  services.chrony = {
    enable = true;
    servers = [ "169.254.169.254" ];
  };

  # mosh（模块会自动放行 UDP 60000-61000）
  programs.mosh.enable = true;

  # btrfs 在线去重，参数照搬旧 Ubuntu /etc/bees 配置
  services.beesd.filesystems.root = {
    spec = "UUID=83ee59a5-0126-4580-898e-c25d90fe9ea9";
    hashTableSizeMB = 256;
    extraOptions = [
      "--strip-paths"
      "--no-timestamps"
    ];
  };
}
