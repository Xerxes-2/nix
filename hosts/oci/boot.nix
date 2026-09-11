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

    # 关掉 gfxterm，否则串口上根本看不到引导菜单。NixOS 默认给 GRUB 配字体，
    # install-grub.pl 就会往 grub.cfg 里写 `terminal_output gfxterm`（纯图形终端，
    # 走 GOP），于是菜单只存在于 VNC 那块虚拟显示器上——救援时想在串口里选上一代
    # 根本选不着。置 null 后 grub.cfg 不再动 terminal_output，沿用 EFI 默认的 `console`
    # （固件 SimpleTextOut/In）。
    #
    # 为什么这样就够：本机 ConOut / ConIn 两个 EFI 变量里各有两条设备路径实例，
    # 第二条就是 UART（节点类型 03 0e），对应 SPCR 里的 pl011,mmio,0x9000000。
    # 所以菜单输出和按键输入会同时走 VNC 和串口。不重启就能核对：
    #   od -An -tx1 /sys/firmware/efi/efivars/ConOut-8be4df61-93ca-11d2-aa0d-00e098032b8c
    #
    # 上游 nixos/modules/virtualisation/oci-common.nix 的 `serial --unit=0` +
    # `terminal_* --append serial` 故意不抄：那是 x86 写法。arm64-efi 的 grub 串口名是
    # efi0（grub-core/term/efi/serial.c 用 "efi%d" 注册，走 EFI_SERIAL_IO_PROTOCOL），
    # 而 --unit=0 拼出的是 com0（grub-core/term/serial.c），只会得到
    # "serial port `com0' isn't found"；就算改成 efi0 也是把同一个 pl011 再驱一遍，
    # 跟 ConOut 里那条重复输出。
    font = null;
    splashImage = null; # 背景图靠 gfxterm 才能画，上面关了它就没意义了
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

  # 保留 OCI 串口控制台（救援通道）。波特率显式写死 115200：不写就沿用固件
  # 设定，而固件改了我们不会知道；上游 nixos/modules/virtualisation/oci-common.nix
  # 也是这个值（抄自 OCI 上 Ubuntu 的 /proc/cmdline）。
  boot.kernelParams = [
    "console=tty1" # VNC 控制台
    "console=ttyAMA0,115200"
  ];

  # 引导卷在 OCI 控制台扩容后，自动把根分区推到盘尾（配合 filesystems.nix 里
  # 根文件系统的 autoResize，一次重启就吃满新容量，不用手工 growpart + btrfs
  # resize）。抄自 nixos/modules/virtualisation/oci-common.nix。
  #
  # 之所以在这台机器上成立：分区是 Ubuntu cloud image 的排法，根分区编号虽是 1，
  # 物理位置却在最后（sda15 ESP @2048、sda16 /boot @206848、sda1 根 @2099200），
  # 后面没有别的分区挡路。换盘或重排分区表前先确认这一点仍然为真。
  boot.growPartition = true;

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
}
