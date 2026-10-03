# Mac mini Mid 2011 Server（Macmini5,3）：i7-2635QM / HD 3000 / 8G，
# SSD 256G + 机械盘 500G 组成的 bcachefs 分层池。
# 起点是 nixos-generate-config 的输出，下面每处改动都写了原因。
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # ===== 引导 =====
  # 这台机器的 Apple 固件上 GRUB EFI 选完启动项即黑屏、内核根本没跑起来
  # （nomodeset / earlyprintk=efi 都无输出；同类报告见 nixpkgs#5829），
  # 所以不用 GRUB，改 systemd-boot：和 rEFInd 一样直接把内核当 EFI 程序启动。
  boot.loader.systemd-boot = {
    enable = true;
    # ESP 只有 1 GB，后面的 bcachefs 成员分区又不能缩（"Cannot shrink yet"），
    # 只能控制每个版本占的空间：initrd 瘦身见下方微码和 bcachefs 模块。
    # 写满后装引导失败，新版本根本进不了启动菜单。
    configurationLimit = 5;
  };
  # 安装时是从 BIOS 兼容模式启动的 U 盘装的，碰不到 EFI 变量；
  # Apple 固件也不依赖 NVRAM 启动项，没有 macOS 时会自己找 EFI/BOOT/BOOTX64.EFI
  # （bootctl --no-variables 会装这个回退路径）。
  boot.loader.efi.canTouchEfiVariables = false;

  # ahci 是手加的：生成配置时 U 盘以 BIOS 兼容模式启动，SATA 处于 IDE 模式，
  # 探测到的是 ata_piix；正式系统走 EFI，Apple 固件把 SATA 切到 AHCI，
  # 少了 ahci 会在 initrd 里找不到根盘。两个都留着，哪种模式都能起。
  boot.initrd.availableKernelModules = [
    "ahci"
    "ata_piix"
    "uhci_hcd"
    "ehci_pci"
    "firewire_ohci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
  ];
  boot.kernelModules = [
    "kvm-intel"
    "wl" # Wi‑Fi，见下方「驱动」
  ];
  boot.initrd.systemd.enable = true;

  # 不追 linuxPackages_latest：bcachefs 已移出主线（6.18 起），现在是 nixpkgs
  # 按 bcachefs-tools 版本单独编译的树外模块，内核太新时它可能还没跟上而编译失败。
  # 想玩新 bcachefs 改 boot.bcachefs.package，不用换内核。
  # TODO revisit: 升级 nixpkgs 后
  #   check: nix build .#nixosConfigurations.macmini.config.system.build.toplevel
  #   then:  bcachefs 模块编译失败就固定到它支持的较旧 LTS（linuxPackages_6_12 等）
  #   last:  2026-10, nixpkgs c59305b：内核 6.18.54 + bcachefs 1.39.6 正常
  boot.kernelPackages = pkgs.linuxPackages;
  # 树外 bcachefs 模块装的时候没去调试信息：initrd 里它压缩后还有 14 MB
  # （解压 86 MB），去掉后 1.2 MB。
  # TODO revisit: 升级 nixpkgs 后
  #   check: grep INSTALL_MOD_STRIP pkgs/by-name/bc/bcachefs-tools/kernel-module.nix
  #   then:  上游加了就删掉这段
  #   last:  2026-10, nixpkgs c59305b：没加
  boot.bcachefs.modulePackage =
    (config.boot.kernelPackages.callPackage config.boot.bcachefs.package.kernelModule { }).overrideAttrs
      (o: {
        makeFlags = o.makeFlags ++ [ "INSTALL_MOD_STRIP=1" ];
      });

  # ===== 驱动 =====
  # tg3（有线 BCM57765）需要 linux-firmware 里的 tigon 固件。
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  # 默认把全部 Intel 微码（15 MB，不压缩）放进每个 initrd；只留本机 CPU
  # （i7-2635QM，签名 0x206a7）的那一份，约 13 KB。
  hardware.cpu.intel.microcodePackage =
    pkgs.runCommand "microcode-intel-206a7" { nativeBuildInputs = [ pkgs.iucode-tool ]; }
      ''
        mkdir $out
        iucode_tool -tr ${pkgs.microcode-intel}/intel-ucode.img -s 0x206a7 \
          --write-earlyfw=$out/intel-ucode.img
      '';
  # Wi‑Fi BCM4331 用闭源 broadcom_sta（wl）而不是主线 b43：这块卡是 HT PHY，
  # b43 在 HT PHY 上只实现了 2.4GHz、11n 也不完整（dmesg: "5 GHz band is
  # unsupported on this PHY"），而机器网口要让给别的设备，Wi‑Fi 得当主力。
  # 代价：wl 上游停维，nixpkgs 标 insecure（CVE-2019-9501/9502，收包堆溢出，
  # 同一无线环境内可远程利用）。接受这个风险，见下方 allowInsecurePredicate。
  # 换回 b43：删掉下面这段，hardware.firmware = [ pkgs.b43Firmware_5_1_138 ]，
  # unfree 白名单把 broadcom-sta 换回 b43-firmware。
  # 注意 wl 下网卡名会变（wlp3s0b1 → wlp3s0），NM 连接不要绑 interface-name。
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  # b43/bcma 会先抢这块卡，wl 就绑不上；ssb/brcmsmac 同为竞争驱动。
  boot.blacklistedKernelModules = [
    "b43"
    "bcma"
    "ssb"
    "brcmsmac"
  ];
  # 只放行这一个包，按 pname 匹配（name 里带内核版本，换内核会变）。
  # TODO revisit: 升级 nixpkgs/内核后
  #   check: nix build .#nixosConfigurations.macmini.config.system.build.toplevel
  #   then:  broadcom-sta 编译失败就固定较旧 LTS 内核，或改插主线驱动的 USB 网卡
  #   last:  2026-10, broadcom-sta 6.30.223.271-63 + 内核 6.18.54
  nixpkgs.config.allowInsecurePredicate = pkg: lib.getName pkg == "broadcom-sta";

  # ===== 文件系统 =====
  # bcachefs 两设备分层池，format 参数（mkfs 时一次性写进超级块）：
  #   --foreground_target=ssd --promote_target=ssd --background_target=hdd
  #   --metadata_replicas=2 --data_replicas=1
  #   --compression=lz4 --background_compression=zstd
  # 写入落 SSD、后台迁到机械盘、热数据缓存回 SSD。数据只一份：坏一块盘会丢数据。
  # 多设备挂载靠 UUID=：mount.bcachefs 会按 UUID 扫齐所有成员设备。
  fileSystems."/" = {
    device = "UUID=f39dee4e-1961-4185-8ebd-d790fa929389";
    fsType = "bcachefs";
  };
  # /home 是 bcachefs 子卷（bcachefs subvolume create），随根一起挂，
  # 可单独 `bcachefs subvolume snapshot`。

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/D48D-8C9E";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  # 每月 scrub，机械盘已通电 7.6 万小时，尽早发现坏块。
  services.bcachefs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };
  # 同理，SMART 监控两块盘。
  services.smartd.enable = true;

  # 8G 内存，用 zram 兜底，不在 bcachefs 上建 swap 文件。
  zramSwap.enable = true;

  nixpkgs.hostPlatform = "x86_64-linux";
}
