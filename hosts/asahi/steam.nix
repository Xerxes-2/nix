{ inputs, pkgs, ... }:
let
  muvmSteam = inputs.nixos-muvm-steam.packages.${pkgs.stdenv.hostPlatform.system}.muvm-steam;
  # The guest has no session bus, and steam-run's default D-Bus configuration
  # has no listen address. /tmp is private to the FHS environment, so keep the
  # explicit configuration in /nix/store, visible on both sides of that boundary.
  # TODO revisit: when nixos-muvm-steam or steam-run changes its D-Bus setup
  #   check: launch Steam without this config and dbus-run-session
  #   then:  remove the private bus if runtime-launcher-service starts normally
  #   last:  2026-11, explicit session bus fixes startup; user confirms Isaac works.
  sessionBus = pkgs.writeText "steam-native-session-bus.conf" ''
    <busconfig>
      <type>session</type>
      <listen>unix:tmpdir=/tmp</listen>
      <auth>EXTERNAL</auth>
      <policy context="default">
        <allow send_destination="*"/>
        <allow receive_sender="*"/>
        <allow own="*"/>
      </policy>
    </busconfig>
  '';
  steamNativeGuest = pkgs.writeShellApplication {
    name = "steam-native-guest";
    text = ''
      if [ ! -x /run/steam-run-free ]; then
        echo "Run muvm-steam-run-free first, then steam-native-guest inside its shell." >&2
        exit 1
      fi
      export PULSE_CLIENTCONFIG=/run/pulse.conf
      # The host launcher uses SHELL to select this guest payload. Restore a
      # real shell before Steam/FHS tools inherit it and try to launch a shell.
      export SHELL=${pkgs.bashInteractive}/bin/bash
      exec /run/steam-run-free dbus-run-session --config-file=${sessionBus} \
        -- "$HOME/Games/steam-native/steam" "$@"
    '';
  };
  steamNative = pkgs.writeShellApplication {
    name = "steam-native";
    text = ''
      # Upstream runs SHELL as its guest payload after setting up Mesa and
      # steam-run. Select our tested payload to avoid an interactive terminal.
      export SHELL=${steamNativeGuest}/bin/steam-native-guest
      exec ${pkgs.lib.getExe muvmSteam}
    '';
  };
  desktop = pkgs.makeDesktopItem {
    name = "steam-native";
    desktopName = "Steam";
    comment = "Steam via muvm and FEX";
    exec = "${steamNative}/bin/steam-native";
    icon = "/home/xerxes2/Games/steam-native/icons/256/steam.png";
    terminal = false;
    categories = [ "Game" ];
  };
in
{
  # Steam and Isaac are verified on the native stack; Fedora is retired.
  environment.systemPackages = [
    desktop
    steamNative
    steamNativeGuest
    muvmSteam
  ];
}
