# BCM4331 逆向用的启动项：抓闭源 wl 的寄存器访问（mmiotrace），给 b43-ht 找参考。
# 默认系统不受影响；只有在 systemd-boot 里选 "mmiotrace" 那一项（或
# `sudo bootctl set-oneshot` 一次性指定）才进入。抓取期间 Wi‑Fi 下线，靠有线 ssh。
#
# 抓取步骤（mmiotrace 会自动下线其它 CPU，只剩一个核）：
#   echo mmiotrace | sudo tee /sys/kernel/tracing/current_tracer
#   sudo cat /sys/kernel/tracing/trace_pipe > wl.mmio &
#   sudo modprobe wl            # 按名字加载不受 blacklist 影响
#   nmcli 连 5GHz / 切信道 …
#   echo nop | sudo tee /sys/kernel/tracing/current_tracer
# 解码、比对工具在 github.com/Xerxes-2/b43-ht 的 tools/。
{
  config,
  lib,
  ...
}:
{
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
    boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
    # wl 必须在 tracer 开启之后才加载，b43 不能先抢卡。
    boot.kernelModules = lib.mkForce [ "kvm-intel" ];
    boot.blacklistedKernelModules = [
      "wl"
      "b43"
      "bcma"
    ];
  };
}
