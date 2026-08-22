# ===== 文件系统（照抄原 fstab，子卷布局不动）=====
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
