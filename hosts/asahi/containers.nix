{ pkgs, ... }:
{
  # Rootless containers, used to run the Fedora Asahi gaming stack (FEX + muvm
  # + Steam) that nixpkgs cannot provide on aarch64: `pkgs.steam` is x86_64
  # only, and FEX needs a downloaded x86 rootfs, which does not fit the Nix
  # model. See hosts/asahi/steam/Containerfile.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  environment.systemPackages = with pkgs; [
    distrobox
  ];
}
