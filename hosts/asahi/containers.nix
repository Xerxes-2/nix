{ inputs, pkgs, ... }:
let
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
      exec /run/steam-run-free dbus-run-session --config-file=${sessionBus} \
        -- "$HOME/Games/steam-native/steam" "$@"
    '';
  };
in
{
  # Keep the tested Fedora gaming stack as a fallback while the native Nix
  # muvm/FEX launcher is tested. programs.steam itself remains x86-only.
  # See hosts/asahi/steam/README.md for both launch paths.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  environment.systemPackages = with pkgs; [
    distrobox
    steamNativeGuest
    inputs.nixos-muvm-steam.packages.${stdenv.hostPlatform.system}.muvm-steam
  ];
}
