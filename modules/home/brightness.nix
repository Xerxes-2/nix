# Automatic panel brightness from the ambient light sensor.
#
# The machine has a working ALS behind the AOP (`aop-sensors-als`, exposed as
# an IIO device); the factory calibration blob that it needs to report real lux
# rather than a constant 0 ships in the vendor firmware package as
# apple/aop-als-cal.bin. Verify both before blaming this module:
#   cat /sys/bus/iio/devices/iio:device1/in_illuminance_input   # must react to light
#   zstd -dc "$(readlink -f /run/current-system/firmware)/apple/aop-als-cal.bin.zst" | wc -c
#                                                              # 193 here, 0 means uncalibrated
# If the calibration is missing, it is regenerated from macOS - boot macOS, run
# `curl -L https://alx.sh/dev | bash` and pick "Rebuild vendor firmware
# package", then update the asahi-firmware flake input.
{ pkgs, ... }:
let
  # Upstream's own example thresholds. These are *labels*, not brightness
  # values: wluma learns a separate curve per bucket, so the only thing that
  # matters is that the lux boundaries split the day into situations that
  # deserve different brightness. Adding buckets makes it learn more slowly.
  wlumaConfig = (pkgs.formats.toml { }).generate "wluma-config.toml" {
    als.iio = {
      path = "/sys/bus/iio/devices";
      thresholds = {
        "0" = "night";
        "20" = "dark";
        "80" = "dim";
        "250" = "normal";
        "500" = "bright";
        "800" = "outdoors";
      };
    };

    output.backlight = [
      {
        name = "eDP-1";
        path = "/sys/class/backlight/apple-panel-bl";
        # wluma also factors in how bright the *contents* of the screen are, so
        # a dark terminal gets more backlight than a white page at the same
        # ambient level. That needs frame capture: niri offers
        # wlr-screencopy-unstable-v1, and the frames are reduced to a luma
        # value on the GPU through Vulkan, which is Honeykrisp here
        # (asahi_icd.aarch64.json). Drop this to "none" for ALS-only operation
        # if capture ever breaks after a niri or Mesa bump.
        capturer = "wayland";
      }
    ];

    # /sys/class/leds/kbd_backlight, driven off the same ALS buckets.
    keyboard = [
      {
        name = "kbd";
        path = "/sys/class/leds/kbd_backlight";
      }
    ];
  };
in
{
  # No nixpkgs module and no unit in the package, so both are declared here.
  #
  # TODO revisit: on wluma bumps - 4.11.1 is well behind upstream main, and the
  # newer config schema is incompatible in both directions
  #   check: wluma --version; then diff the config schema against
  #          https://github.com/maximbaz/wluma/blob/<version>/config.toml
  #   then:  main has moved to ext-image-copy-capture-v1, added an [idle]
  #          section (would overlap with whatever DMS idle handling exists by
  #          then) and a per-output `gamma` flag. That flag matters: newer
  #          wluma takes wlr-gamma-control *exclusively* for its dim/colour
  #          temperature feature, which would fight both DMS night light and
  #          the niri software-gamma patch. Set `gamma = false` when bumping.
  #   last:  2026-08, 4.11.1 - no [idle], no gamma, uses wlr-screencopy
  xdg.configFile."wluma/config.toml".source = wlumaConfig;

  systemd.user.services.wluma = {
    Unit = {
      Description = "Automatic brightness based on ambient light and screen contents";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wluma}/bin/wluma";
      Restart = "on-failure";
      RestartSec = 5;
      # Brightness is written through logind's D-Bus SetBrightness rather than
      # sysfs (wluma picks this automatically), so the service needs no
      # privileges and no udev rule - it logs
      #   "Using DBUS for /sys/class/backlight/apple-panel-bl"
      # at debug level when that path is taken.
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.packages = [ pkgs.wluma ]; # for the `wluma` CLI
}
