# Laptop power behaviour: memory pressure handling, battery wear limit and the
# physical keys.
{ pkgs, ... }:
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
  #
  # TODO revisit: after systemd or nixpkgs bumps - this drop-in is the only
  # thing keeping systemd-oomd useful, and it fails silently if the unit paths
  # move
  #   check: oomctl        # the user app.slice must be listed under
  #                        # "Monitored memory pressure cgroups"
  #   then:  if the NixOS module ever monitors app.slice itself, delete this
  #   last:  2026-09, systemd 261.2 - nixpkgs oomd module still leaves
  #          enableRootSlice / enableSystemSlice / enableUserSlices all off,
  #          and even enableUserSlices only touches user@.slice, not app.slice
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

  # Stop charging at 80% to slow battery wear.
  #
  # The threshold is enforced by the SMC, not by the kernel, which is why it
  # survives s2idle. macsmc-power only forwards it, and on modern firmware
  # (`has_chwa`) `charge_control_end_threshold` is a flag in disguise: the
  # driver writes `CHWA = (value <= 95)` and the firmware applies its own fixed
  # 80% cap, so the attribute always reads back exactly 80 and any value below
  # 95 means the same thing. Older firmware (`has_chls`) takes a real number.
  #
  # `charge_control_start_threshold` is deliberately not set: the driver accepts
  # writes and discards them ("not configurable independently"), the value is
  # always end - 5, so this machine reads 75 no matter what is written. See
  # macsmc_battery_set_property() in drivers/power/supply/macsmc-power.c of the
  # Asahi tree.
  #
  # sysfs resets to 100 on every boot, and a udev rule is the documented way to
  # make it stick: https://social.treehouse.systems/@AsahiLinux/110560192550506827
  #
  # TODO revisit: after kernel bumps - the thresholds are Asahi-only, the
  # macsmc-power that went upstream in 7.1 exposes charge_behaviour and no
  # thresholds at all, so this rule would go silently dead on a mainline driver
  #   check: cat /sys/class/power_supply/macsmc-battery/charge_control_end_threshold
  #          # 80 = in effect, 100 = no limit, ENOENT = driver dropped it
  #   then:  fall back to charge_behaviour, or drop the rule if it is a no-op
  #   last:  2026-09, 7.1.12 - macsmc-power still registers
  #          CHARGE_CONTROL_{START,END}_THRESHOLD (gated on CHWA/CHLS), so the
  #          rule still has something to write. Read from the kernel source on
  #          oci; sysfs not re-read on the machine itself.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="macsmc-battery", ATTR{charge_control_end_threshold}="80"
  '';

  # Let the P-clusters reach their top three P-states (3360/3408/3504 MHz).
  #
  # The device tree ships those three as `turbo-mode` OPPs, so the cpufreq core
  # hides them behind the boost knob: `scaling_available_frequencies` stops at
  # 3264 MHz, which is 93% of the 3504 MHz macOS uses and most of the
  # single-threaded gap against it.
  #
  # They were originally held back because the DVFS controller only grants a
  # boost state while the *rest* of the cluster sits in deep idle, and Asahi had
  # no deep idle, so the states were unreachable and were left out of the DT "to
  # avoid confusing users":
  #   https://lists.openwall.net/linux-kernel/2022/10/24/116
  # That blocker is gone here - this kernel has the apple_idle driver with a
  # "CPU PD" (CPU/cluster powered down) state, which is the condition the
  # hardware is looking for. Re-check before trusting this after a kernel bump:
  #   cat /sys/devices/system/cpu/cpu4/cpuidle/state1/name
  #
  # That condition also bounds the win: this is a 4E + 3P + 3P machine (policy0,
  # policy4, policy7), and with a whole P-cluster loaded nothing in it is idle,
  # so the hardware keeps clamping to 3264. Lightly-threaded work only, never
  # all-core runs. Nothing is forced either - the frequency is only *requested*,
  # and the hardware still decides.
  #
  # Done from tmpfiles rather than the udev block above because the knob is
  # /sys/devices/system/cpu/cpufreq/boost, a cpufreq-core attribute rather than a
  # device: `udevadm info` on that path answers "Unknown device", so ATTR{} has
  # nothing to match. Writing the global flag also updates the per-policy ones
  # since 218a06a79d9a ("cpufreq: Support per-policy performance boost").
  #
  # Measured here, one core loaded with its cluster siblings in CPU PD:
  #   schedutil    requested 3264 -> granted 3264
  #   performance  requested 3504 -> granted 3504
  # So the hardware does grant boost, and deep idle is not the blocker on this
  # kernel. schedutil simply never asks, which is an upstream bug rather than
  # anything Apple-specific: it maps utilisation through capacity_freq_ref, a
  # deliberately fixed anchor (9942cb22ea45) latched at boot while boost was
  # still off, so the request saturates at exactly the non-boost ceiling. Fix is
  # in flight and not in 7.1:
  #   https://lore.kernel.org/linux-pm/20260806044230.909961-1-sibi.sankar@oss.qualcomm.com/
  # Keep the flag regardless: it is inert today and starts paying off on its own
  # once that lands, without needing to remember any of this.
  #
  # TODO revisit: after every kernel bump
  #   check: taskset -c 4 timeout 5 bash -c 'while :; do :; done' &
  #          cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq
  #          # 3264000 = schedutil still capped, 3504000 = the fix landed
  #   then:  delete the cpu-boost unit below, the tmpfiles flag is enough
  #   last:  2026-09, 7.1.12 - fix still not in the tree: capacity_freq_ref is
  #          still latched from policy->cpuinfo.max_freq at
  #          CPUFREQ_CREATE_POLICY (arch_topology.c:407) and nothing in
  #          arch_topology touches boost. Not re-measured on the machine.
  systemd.tmpfiles.rules = [
    "w /sys/devices/system/cpu/cpufreq/boost - - - - 1"
  ];

  # Until then the only way to reach boost is the performance governor. Running
  # that full time on a laptop pins the P-cores to 3504 for every burst of work
  # that lands on them, which is the wrong default on battery - so make it an
  # explicit, reversible opt-in:
  #   sudo systemctl start cpu-boost   # benchmark, big build, ...
  #   sudo systemctl stop  cpu-boost
  # The E-cluster (policy0) is left alone on purpose: it has no boost states,
  # and it is where idle and light work should be staying anyway.
  systemd.services.cpu-boost = {
    description = "Pin the P-clusters to their maximum P-state, boost included";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "cpu-boost-on" ''
        for p in 4 7; do
          echo performance > /sys/devices/system/cpu/cpufreq/policy$p/scaling_governor
        done
      '';
      ExecStop = pkgs.writeShellScript "cpu-boost-off" ''
        for p in 4 7; do
          echo schedutil > /sys/devices/system/cpu/cpufreq/policy$p/scaling_governor
        done
      '';
    };
  };

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
