# Laptop power behaviour: memory pressure handling, battery wear limit and the
# physical keys.
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

  # The other half of running out of 16G: kill one application before the
  # desktop grinds to a halt, which is roughly what macOS does with jetsam.
  #
  # NixOS enables systemd-oomd by default but leaves all three of
  # enableRootSlice / enableSystemSlice / enableUserSlices off, so the daemon
  # runs while monitoring nothing whatsoever - `oomctl` lists no cgroups at all.
  #
  # `systemd.oomd.enableUserSlices = true` is the obvious fix and the wrong one
  # here. It arms user.slice, whose only child is user-1000.slice, so "kill the
  # worst descendant" means killing the whole session; and since that monitored
  # ancestor is owned by root while the candidates below it are owned by UID
  # 1000, systemd-oomd deliberately ignores every ManagedOOMPreference=
  # exemption set inside the session (systemd.resource-control(5)).
  #
  # Monitoring app.slice inside the user manager instead gives per-application
  # granularity: the candidates are the individual app cgroups (the browser and
  # Telegram run as run-p*.scope, terminals as app-niri-alacritty-*.scope), the
  # compositor cannot be touched because niri.service lives in session.slice,
  # and exemptions are honoured because monitor and candidates share a UID.
  #
  # 50% is Fedora's desktop value. The metric is the fraction of a 10s window in
  # which *every* task in the cgroup was stalled, sustained for 30s, so this
  # only fires when the session is already unusable. Raise it towards the 80%
  # the NixOS module uses if anything ever gets killed that should not have been.
  systemd.user.units."app.slice" = {
    overrideStrategy = "asDropin";
    text = ''
      [Slice]
      ManagedOOMMemoryPressure=kill
      ManagedOOMMemoryPressureLimit=50%
    '';
  };

  # DMS is session infrastructure that merely happens to sit in app.slice - the
  # bar, notifications, launcher and lock screen all die with it. At ~400M it
  # would never win the "most reclaim activity" contest against a browser
  # anyway, but make that explicit. `avoid` rather than `omit`, so a genuine
  # runaway in DMS itself can still be dealt with as a last resort.
  #
  # This merges into the unit the DMS module already declares; declaring
  # `systemd.user.units."dms.service"` here instead would be a second, competing
  # definition of the same unit and fails to evaluate.
  systemd.user.services.dms.serviceConfig.ManagedOOMPreference = "avoid";

  # Stop charging at 80% to slow battery wear. Asahi's macsmc driver emulates
  # the thresholds in the kernel (the SMC has no native support), so the limit
  # keeps being enforced even in s2idle:
  #   https://github.com/AsahiLinux/linux/commit/6eb70e021ccaae0408e5a746b65848b811c23caa
  #
  # sysfs resets to 100 on every boot, and a udev rule is the documented way to
  # make it stick: https://social.treehouse.systems/@AsahiLinux/110560192550506827
  # Start before end - the driver requires start <= end, and both default to 100.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="macsmc-battery", ATTR{charge_control_start_threshold}="70", ATTR{charge_control_end_threshold}="80"
  '';

  services.logind.settings.Login = {
    # On this keyboard the power key *is* the Touch ID key, immediately right of
    # Delete, so a mistyped Delete must not power the machine off. A deliberate
    # long press still does (systemd defaults that to "ignore").
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";

    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    # Locking on suspend is not a logind setting (contrary to what several
    # configs on GitHub claim - `LockScreenOnSuspend=` does not exist in
    # logind.conf). DMS does it itself: enable "loginctl lock integration" and
    # "lock before suspend" in its settings.
  };
}
