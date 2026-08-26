{ inputs, pkgs, ... }:
{
  imports = [
    inputs.nixos-apple-silicon.nixosModules.default
    # Run `sudo nixos-generate-config --show-hardware-config | tee hardware-configuration.nix`
    # and uncomment this line.
    ./hardware-configuration.nix
    ./gui.nix
    ./input.nix
    ./containers.nix
  ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = false;

    kernelParams = [
      "appledrm.show_notch=1"
    ];
  };

  hardware.asahi = {
    enable = true;
    setupAsahiSound = true;
    peripheralFirmwareDirectory = inputs.asahi-firmware;
  };

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];
  };
  networking = {
    hostName = "asahi";
    networkmanager.enable = true;
    networkmanager.wifi.backend = "iwd";
    wireless.iwd.enable = true;
  };

  environment.systemPackages = with pkgs; [
    asahi-bless
  ];

  users.mutableUsers = true;

  users.users.xerxes2 = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      # DMS reads /dev/input/event* to track the keyboard layout and
      # Caps/Num lock state.
      "input"
    ];
  };

  security.sudo.enable = true;

  system.stateVersion = "25.05";
}
