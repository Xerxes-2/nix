# ===== 文件系统 =====
#
# 子卷布局最初照抄 Ubuntu 时代的 fstab，2026-08 拆出 @nix 和 @varlib：
#
#   @        /            系统根（可从 flake 重建，不值得快照）
#   @nix     /nix         store，全盘最大且完全可复现
#   @varlib  /var/lib     服务状态的真正所在地 → snapper 快照
#   @home    /home        用户数据（dufs-data）→ snapper 快照
#   @log     /var/log     日志，写入频繁、无保留价值
#   @cache   /var/cache   缓存，同上
#   @tmp     /var/tmp     临时文件，同上
#
# 为什么 /nix 要单独拆：store 是从 flake 可复现的，任何 @ 的快照或 send/receive
# 都不该把它拖上；回滚 store 还会和 generation 语义打架。asahi 一直是 @nix，
# 这次把 oci 对齐。
#
# 为什么 /var/lib 要单独拆：vaultwarden / wakapi / SillyTavern / ntfy 的状态全在
# 这里，而快照原先只盖 /home（容器时代的遗留假设，见 services/misc.nix）。
#
# /nix 和 /var/lib 都在 nixos/lib/utils.nix 的 pathsNeededForBoot 里，stage-1 会
# 自动挂载，无需显式 neededForBoot。
{
  config,
  pkgs,
  lib,
  ...
}:
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
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@";
    # 引导卷扩容后自动把 btrfs 撑满（分区那一半由 boot.growPartition 做，见
    # boot.nix）。只在 "/" 上标一次就够：下面那六个挂的是同一个 btrfs，
    # 文件系统级的 resize 是全局的，重复标只会多跑几个 systemd-growfs 单元。
    # 实现是挂载选项 x-systemd.growfs（nixos/modules/tasks/filesystems.nix），
    # btrfs 在 resizableFSes 名单里。
    autoResize = true;
  };
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@nix";
  };
  fileSystems."/var/lib" = {
    device = "/dev/disk/by-uuid/${btrfsUuid}";
    fsType = "btrfs";
    options = btrfsOpts "/@varlib";
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
}
