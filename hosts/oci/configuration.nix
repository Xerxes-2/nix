# OCI A1.Flex aarch64 — 由 Ubuntu 26.04 经 NIXOS_LUSTRATE 原地迁移
{ config, pkgs, lib, ... }:

let
  btrfsUuid = "83ee59a5-0126-4580-898e-c25d90fe9ea9";
  btrfsOpts = subvol: [
    "subvol=${subvol}"
    "noatime"
    "compress-force=zstd:3"
    "discard=async"
  ];
in
{
  # ===== 引导 =====
  # ESP 只有 98M，放不下 aarch64 内核 → 用 GRUB：内核放 891M 的 ext4 /boot，
  # ESP 里只有 grub 的 efi 可执行文件
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    # OCI 固件对 efibootmgr 写的 NVRAM 启动项不可靠：直接装到固件回退路径
    # EFI/BOOT/BOOTAA64.EFI，不依赖 NVRAM
    efiInstallAsRemovable = true;
    configurationLimit = 4;
  };
  boot.loader.efi = {
    canTouchEfiVariables = false;
    efiSysMountPoint = "/boot/efi";
  };

  # 迁移期间曾设为 false（NIXOS_LUSTRATE 只有脚本版 stage-1 实现）；
  # lustrate 已完成，改回 unstable 默认的 systemd stage-1。
  boot.initrd.systemd.enable = true;

  # 最新主线内核（启动失败可在 GRUB 选上一代回滚）
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 保留 OCI 串口控制台（救援通道）
  boot.kernelParams = [ "console=tty1" "console=ttyAMA0" ];

  # BBR 拥塞控制：海外 VPS 对外提供服务，吞吐/延迟收益明显
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
  };

  # OCI 启动卷走 virtio-scsi；缺这些模块 stage-1 找不到根盘
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "nvme"
    "sd_mod"
  ];

  boot.tmp.useTmpfs = true; # /tmp = tmpfs，与 Ubuntu 现状一致

  # ===== 文件系统（照抄原 fstab，子卷布局不动）=====
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@";
  };
  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@home";
  };
  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@log";
  };
  fileSystems."/var/cache" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@cache";
  };
  fileSystems."/var/tmp" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@tmp";
  };
  fileSystems."/home/ubuntu/.local/share/containers" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@containers";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/71551c63-1196-417c-b4ce-2898a9c58004";
    fsType = "ext4";
  };
  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/F8E6-38E1";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50; # zstd 压缩比通常 3:1+，实际内存占用远小于名义值
  };

  # ===== 网络 =====
  networking.hostName = "instance-20260821-1942";
  networking.useNetworkd = true;
  networking.useDHCP = true; # OCI DHCP 下发 IP/路由/MTU
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ]; # 其余服务走 cloudflared 隧道

  time.timeZone = "Australia/Melbourne";

  # ===== 用户 =====
  users.groups.ubuntu.gid = 1001;
  users.users.ubuntu = {
    isNormalUser = true;
    uid = 1001;
    group = "ubuntu";
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    linger = true; # 开机即拉起 user 服务（容器）
    # 关键：钉死原 subuid/subgid range，rootless 容器 :U 卷的文件属主依赖它
    autoSubUidGidRange = false;
    subUidRanges = [ { startUid = 165536; count = 65536; } ];
    subGidRanges = [ { startGid = 165536; count = 65536; } ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUmTvXl/5tGe4e+alerNLGctJvGjeIWIrq3TeTitCUF2LLuWF49ea7j5XocB5TpBP1KcjXuzUuD0qBBrOdnKC0oX781MbiwdHSf0Cl6R5ZocyJl9Oxsu2Szjxq6Gkhw5u6dumbQHMV9fcPVSHDDuuSBjD3Cc0T1lPOUd3x2FJjebFEVDESXFJPZfKbzAgcBdxccl2T3lqEJ5RX8PeZ4RFK6yB+6G8jaqq8I4IoZU0P0toI568eRm3exGg8MtafY0kWk/FAuCRgmw+dQb2GjwPwP7cHprupbZNRkZaS/v5YJGudMXsa7nTGqQXyt5wAzPpTbvkkJbLhvhb35wN3eeFZ oracle"
    ];
    # 哈希由切换向导写入，lustrate 白名单保留 etc/secrets（mutableUsers 下仅首次建用户时生效）
    hashedPasswordFile = "/etc/secrets/ubuntu.hash";
  };
  # 串口控制台救援登录用，同上由向导写入
  users.users.root.hashedPasswordFile = "/etc/secrets/root.hash";

  # 与现状一致：ssh 仅密钥登录，sudo 免密（密码仅串口救援登录用）
  security.sudo.wheelNeedsPassword = false;

  # rootless quadlet 需要系统层显式开启（装 podman + systemd user generator）
  virtualisation.quadlet.enable = true;

  programs.fish.enable = true;
  programs.nix-ld.enable = true; # 兼容家目录里非 nix 编译的二进制

  # ===== 服务 =====
  services.openssh = {
    enable = true;
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

  # wakapi 原生服务（从 rootless 容器迁入，2026-08）。DynamicUser，
  # 数据在 /var/lib/private/wakapi/wakapi.db（/var/lib/wakapi 是 symlink）。
  # salt 必须与容器时代一致（密码哈希依赖它）：/etc/secrets/wakapi.env
  services.wakapi = {
    enable = true;
    environmentFiles = [ "/etc/secrets/wakapi.env" ];
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

  # restic 每日异地备份→ OCI Object Storage（复用 Ubuntu 时代的 vps-backup 仓库）。
  # 旧快照 host=OCI-Ubuntu-arm，新的 host=oci；forget 按 paths 分组，
  # 路径集不变故旧快照会随保留策略自然淘汰。
  # 凭据：/etc/secrets/restic.{password,env}（见 MIGRATION.md 的命令式 secrets 惯例）。
  services.restic.backups.oci = {
    repository = "s3:https://REDACTED.compat.objectstorage.ap-sydney-1.oraclecloud.com/vps-backup";
    passwordFile = "/etc/secrets/restic.password";
    environmentFile = "/etc/secrets/restic.env";
    paths = [
      "/home/ubuntu/dufs-data"
      "/var/lib/private/wakapi"
      "/home/ubuntu/sillytavern-data"
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

  # cloudflared tunnel（token 方式）。
  # TODO(Phase 3 前必做): 创建 /etc/secrets/cloudflared.env，内容一行:
  #   TUNNEL_TOKEN=eyJhIjoi...（原 unit 里的 token）
  # chmod 600 / chown root。lustrate 白名单里有 etc/secrets，会保留。
  systemd.services.cloudflared = {
    description = "cloudflared tunnel";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      TimeoutStartSec = 15;
      EnvironmentFile = "/etc/secrets/cloudflared.env";
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate tunnel run";
      Restart = "on-failure";
      RestartSec = "5s";
      DynamicUser = true;
    };
  };

  # ===== Nix =====
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "@wheel" ];
  };
  # 定时硬链接去重，替代 auto-optimise-store（后者拖慢每次构建）
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    htop
    btrfs-progs
    # 从 Ubuntu apt 手动安装集迁移而来
    bottom # btm
    btop
    bubblewrap
    chromium
    compsize
    duperemove
    eza
    fastfetch
    fio
    gh
    kitty.terminfo
    lnav
    nano
    restic
    ripgrep
    rsync
    sqlite
    tokei
    tree
    unar
    unzip
    wget
    zip
  ];

  # mosh（模块会自动放行 UDP 60000-61000）
  programs.mosh.enable = true;

  # btrfs 在线去重，参数照搬旧 Ubuntu /etc/bees 配置
  services.beesd.filesystems.root = {
    spec = "UUID=83ee59a5-0126-4580-898e-c25d90fe9ea9";
    hashTableSizeMB = 256;
    extraOptions = [ "--strip-paths" "--no-timestamps" ];
  };

  # 无头服务器：裁掉 NixOS 手册等文档，减小闭包、加快 rebuild
  documentation.nixos.enable = false;

  # 首次安装即为该版本，之后勿改
  system.stateVersion = "26.05";
}
