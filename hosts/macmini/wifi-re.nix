# BCM4331 逆向用的启动项：给 b43 补 5GHz/11n 前，先抓闭源 wl 的寄存器访问。
# 默认系统不受影响；只有在 systemd-boot 里选 "mmiotrace" 那一项（或
# `sudo bootctl set-oneshot` 一次性指定）才进入。抓取期间 Wi‑Fi 下线，靠有线 ssh。
#
# 抓取步骤（mmiotrace 会自动下线其它 CPU，只剩一个核）：
#   echo mmiotrace | sudo tee /sys/kernel/tracing/current_tracer
#   sudo cat /sys/kernel/tracing/trace_pipe > wl.mmio &
#   sudo modprobe wl            # 按名字加载不受 blacklist 影响
#   nmcli 连 5GHz / 切信道 …
#   echo nop | sudo tee /sys/kernel/tracing/current_tracer
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # 打了 5GHz 实验补丁的 b43（见 b43-ht/）。平时仍用 wl，b43 留在黑名单里不会自动加载；
  # 实验时接网线手动切：
  #   sudo rmmod wl; sudo modprobe bcma; sudo modprobe b43 htphy_5ghz=1   # 1=只收不发
  # 切回：sudo rmmod b43 bcma; sudo modprobe wl
  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ./b43-ht/module.nix { debug = true; })
  ];
  hardware.firmware = [ pkgs.b43Firmware_5_1_138 ];

  specialisation.mmiotrace.configuration = {
    system.nixos.tags = [ "mmiotrace" ];
    # 允许经 /dev/mem 读已被驱动占用的 MMIO（IO_STRICT_DEVMEM），用来在 wl 运行时
    # 读 D11 寄存器和 b43 对照。只在这个逆向启动项里放开。
    boot.kernelParams = [ "iomem=relaxed" ];
    boot.kernelPatches = [
      {
        name = "mmiotrace";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          MMIOTRACE = yes;
        };
      }
    ];
    # wl 必须在 tracer 开启之后才加载，否则抓不到初始化过程。
    boot.kernelModules = lib.mkForce [ "kvm-intel" ];
    boot.blacklistedKernelModules = [ "wl" ];
  };
}
