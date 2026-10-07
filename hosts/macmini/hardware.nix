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
  boot.kernelModules = [ "kvm-intel" ];
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
  # 散热：Wi‑Fi 满载（单核忙）时 SMC 风扇从 2300 rpm 起步太慢，核心冲到
  # 100°C 并触发降频，开满 5500 rpm 也压不住；2026-10-07 疑似一次过热断电。
  # 只提风扇下限到 4000 rpm：短测约 70°C，但 2 小时混合长测仍有约 30 分钟
  # 在 95–100°C 降频。再关掉睿频：Wi‑Fi 满载最高 76°C，TCP RX 231、TX 165
  # Mbit/s，与长测中降频后的吞吐相同。
  # TODO revisit：清灰换硅脂后复测，散热恢复就删掉。
  systemd.services.macmini-fan-min = {
    description = "Raise the SMC fan minimum and disable turbo until the cooling is serviced";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for i in $(seq 1 30); do
        [ -w /sys/devices/platform/applesmc.768/fan1_min ] && break
        sleep 1
      done
      echo 4000 > /sys/devices/platform/applesmc.768/fan1_min
      echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
    '';
  };
  # Wi‑Fi BCM4331：主线 b43 在这块 HT PHY 上只有 2.4GHz、没有 11n，所以用自己补的
  # b43-ht（github.com/Xerxes-2/b43-ht，flake input）：5GHz、11n、40 MHz，近距离吞吐
  # 与闭源 wl 持平。模块只编 b43.ko 放进 updates/ 覆盖主线版本；顺带关掉 NM 扫描
  # 随机 MAC（mac80211 不能在线改 MAC，NM 每次连接前关开接口会让扫描失败）。
  # debug 版带 debugfs（restart、shm/mmio 读写），出问题时好查。
  hardware.b43-ht = {
    enable = true;
    debug = true;
    # RX 和 TX 状态走 NAPI + GRO：TCP RX 约 200 → 235 Mbps（wl 约 210）。
    # 默认关闭的选项；出问题时删掉这一行即回到 IRQ 线程直接上交。
    # TODO revisit：BA 会话 drain/epoch 尚未处理，长期观察后再决定是否保留。
    extraOptions = [ "htphy_napi=1" ];
  };

  # 备用：开机选 "wl" 启动项回到闭源 broadcom_sta。b43-ht 观察一段时间没问题就删掉
  # 这个启动项、insecure 白名单和 unfree 白名单里的 broadcom-sta。
  # wl 是停维驱动，nixpkgs 标 insecure（CVE-2019-9501/9502，收包堆溢出，同一无线环境
  # 内可远程利用）。注意 wl 下网卡名不同（wlp3s0 而不是 wlp3s0b1），NM 连接不要绑
  # interface-name。
  specialisation.wl.configuration = {
    system.nixos.tags = [ "wl" ];
    hardware.b43-ht.enable = lib.mkForce false;
    boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
    boot.kernelModules = [ "wl" ];
    # b43/bcma 会先抢这块卡，wl 就绑不上；ssb/brcmsmac 同为竞争驱动。
    boot.blacklistedKernelModules = [
      "b43"
      "bcma"
      "ssb"
      "brcmsmac"
    ];
  };
  # 只放行这一个包，按 pname 匹配（name 里带内核版本，换内核会变）。
  # TODO revisit: 升级 nixpkgs/内核后
  #   check: nix build .#nixosConfigurations.macmini.config.system.build.toplevel
  #   then:  broadcom-sta 编译失败就删掉 wl 启动项（b43-ht 已是日常驱动）
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
