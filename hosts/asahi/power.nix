# Laptop power behaviour: memory pressure handling and battery wear limit.

{ ... }:
{
  # zswap instead of zram.
  #
  # Fedora Asahi Remix shipped zram plus an 8G swapfile on 8/16G machines,
  # concluded that combination causes premature OOM kills (typically Firefox),
  # and since 2024-11 moved those machines to zswap with a 12G swapfile. Only
  # >=24G machines keep zram-only:
  #   https://discussion.fedoraproject.org/t/psa-transitioning-from-zram-swap-to-zswap/138256
  #   https://github.com/nix-community/nixos-apple-silicon/issues/253
  #
  # The difference that matters: zram is a fixed block device that competes for
  # the same RAM it is supposed to save, while zswap is a compressed *cache* in
  # front of a real swap file, so cold pages can be written out to disk and the
  # on-disk swap is actually reachable before the OOM killer runs. This is a
  # 16G M2 Pro, so follow the 16G layout.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 12 * 1024; # MiB
    }
  ];

  boot.kernelParams = [
    # Only the on switch and the pool cap are needed here:
    # `zswap.compressor` already defaults to zstd on this kernel, and zsmalloc
    # is the only zpool left since zbud/z3fold were removed, so the
    # `zswap.compressor=zstd zswap.zpool=zsmalloc` half of the older recipes is
    # a no-op now (verify with /sys/module/zswap/parameters/*).
    "zswap.enabled=1"
    # Cap of the compressed pool, not a reservation. The kernel default is 20;
    # 50 is the Fedora Asahi value quoted in nixos-apple-silicon#253.
    "zswap.max_pool_percent=50"
  ];

  boot.kernel.sysctl = {
    # Pushing a page into a compressed RAM cache is far cheaper than dropping
    # page cache and re-reading it, so let the kernel swap early rather than
    # thrash the file cache. Lower this back towards 60 if interactive latency
    # ever suffers.
    "vm.swappiness" = 180;
    # Swap readahead reads 2^n neighbouring pages; with zswap every one of them
    # has to be decompressed, and locality on swap-in is poor. Read one page.
    "vm.page-cluster" = 0;
  };

  # Stop charging at 80% to slow battery wear. Asahi's macsmc driver emulates
  # the thresholds in the kernel (the SMC has no native support), so the limit
  # keeps being enforced even in s2idle:
  #   https://github.com/AsahiLinux/linux/commit/6eb70e021ccaae0408e5a746b65848b811c23caa
  #
  # sysfs resets to 100 on every boot, and a udev rule is the documented way to
  # make it stick: https://social.treehouse.systems/@AsahiLinux/110560192550506827
  # Start before end - the driver requires start <= end, and both default to 100.
  # The driver then clamps start up to end - 5, so this lands on 75/80.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="macsmc-battery", ATTR{charge_control_start_threshold}="70", ATTR{charge_control_end_threshold}="80"
  '';
}
