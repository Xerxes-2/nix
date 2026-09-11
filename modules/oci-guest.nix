# ===== OCI（Oracle Cloud Infrastructure）Ampere A1 客户机的环境常识 =====
#
# 这里只放「因为跑在 OCI 的 aarch64 虚机上所以必须这样」的东西，不放「这台机器
# 干什么」。凡是换一台 A1 实例还得原样再写一遍的，就属于这里；带具体 UUID、
# 主机名、服务、分区布局的，留在各自的 hosts/<host>/。
#
# 相当于我们自己的 nixos/modules/virtualisation/oci-common.nix。不直接用上游那个：
# 它是给 oci-image.nix 造 qcow2 镜像用的（by-label 的 ext4 根、make-disk-image、
# oci.efi 开关），跟我们这种在现成实例上装出来的机器只有环境事实这一小块交集；
# 而且它的串口那段在 aarch64 上是坏的（见下面 grub 注释）。
{
  config,
  lib,
  ...
}:
{
  # ---- 串口控制台 ----
  #
  # OCI 控制台的串口连接是这类机器唯一的带外通道：SSH 起不来、网络配错、initrd
  # panic，全靠它。两个 console= 都留：tty1 是 VNC 那块虚拟显示器，ttyAMA0 是串口。
  #
  # 波特率显式写死 115200，不写就沿用固件设定，而固件改了我们不会知道。实际上
  # 这台的 SPCR 写的是 9600、EFI ConOut 里的 UART 节点写的是 38400，三个值互不
  # 一致却都能用——pl011 是模拟的，波特率纯属摆设。写 115200 是为了跟上游
  # （nixos/modules/virtualisation/oci-common.nix，抄自 OCI 上 Ubuntu 的 cmdline）
  # 对齐，消除「固件默认是多少」这个不确定性，不是它让串口能用。
  boot.kernelParams = [
    "console=tty1"
    "console=ttyAMA0,115200"
  ];

  # GRUB 菜单也得出现在串口上，否则「启动失败就在菜单里选上一代」这条救援路径
  # 只在 VNC 里成立，而串口才是你出事时手边那个。
  #
  # NixOS 默认给 GRUB 配字体，install-grub.pl 据此往 grub.cfg 写
  # `terminal_output gfxterm`——纯图形终端，只走 GOP。置 null 后 grub.cfg 不再动
  # terminal_output，沿用 EFI 默认的 `console`，即固件的 SimpleTextOut/In。
  #
  # 为什么这样就够：OCI 固件的 ConOut / ConIn 两个 EFI 变量里各有两条设备路径
  # 实例，第二条就是 UART（节点类型 03 0e），对应 SPCR 里的 pl011,mmio,0x9000000。
  # 所以菜单输出和按键输入会自动同时走 VNC 和串口。换了实例想复核，不用重启：
  #   od -An -tx1 /sys/firmware/efi/efivars/ConOut-8be4df61-93ca-11d2-aa0d-00e098032b8c
  # 看有没有 03 0e 开头的节点。
  #
  # 上游 oci-common.nix 那三行（`serial --unit=0 --speed=115200 …` +
  # `terminal_input/output --append serial`）故意不抄，那是 x86 写法：arm64-efi 的
  # grub 串口名是 efi0（grub-core/term/efi/serial.c 用 "efi%d" 注册，走
  # EFI_SERIAL_IO_PROTOCOL），而 --unit=0 拼出的是 com0（grub-core/term/serial.c），
  # 只会得到 "serial port `com0' isn't found"，而且报错还淹没在 gfxterm 里看不见。
  # 就算改成 efi0，也不过是把 ConOut 已经在驱的那个 pl011 再驱一遍，重复输出。
  boot.loader.grub = lib.mkIf config.boot.loader.grub.enable {
    font = null;
    splashImage = null; # 背景图靠 gfxterm 才能画，上面关了它就没意义了
  };

  # ---- 磁盘 ----
  #
  # 在 OCI 控制台把引导卷调大之后，开机自动把根分区推到盘尾；文件系统那一半靠
  # 对应 fileSystems 上的 autoResize（挂载选项 x-systemd.growfs）。省掉手工
  # growpart + btrfs filesystem resize max。
  #
  # 前提是根分区物理上在盘尾、后面没有别的分区挡路。两台都满足，但成立的原因
  # 不同：oci 是 Ubuntu cloud image 的排法（编号是 1，物理在 sda15/sda16 之后），
  # 新机是 disko 自己排的。换盘或重排分区表后复核：
  #   for p in /sys/block/sda/sda*; do echo "$p $(cat $p/start)"; done
  # 根分区的 start 必须最大。
  boot.growPartition = true;

  # OCI 的引导卷走 virtio-scsi；缺这些模块 stage-1 找不到根盘
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "nvme"
    "sd_mod"
  ];

  # ---- 网络 ----
  #
  # IP / 路由 / MTU 全由 OCI 的 DHCP 下发，不要手配。
  networking.useNetworkd = lib.mkDefault true;
  networking.useDHCP = lib.mkDefault true;

  # VCN 内部 NTP（链路本地地址，同时也是 IMDS 的地址），低延迟且必达
  services.chrony.servers = lib.mkDefault [ "169.254.169.254" ];
}
