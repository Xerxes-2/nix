# ===== 引导 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
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
    # gfxterm 的关闭（font/splashImage = null，串口上能看见菜单的关键）在
    # modules/oci-guest.nix，两台 OCI 机器共用。
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

  # 串口控制台参数、growPartition、virtio 模块都在 modules/oci-guest.nix。

  # BBR 拥塞控制：海外 VPS 对外提供服务，吞吐/延迟收益明显
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
  };

  boot.tmp.useTmpfs = true; # /tmp = tmpfs，与 Ubuntu 现状一致
}
