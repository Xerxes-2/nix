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
    # The Asahi ESP is 504M and also holds vendorfw (63M), the macOS-side
    # asahi/ directory (54M) and m1n1 (8M). Every generation with a new kernel
    # copies a 65M Image plus a 29M initrd in there - the kernel is a full
    # all-modules NixOS build - so a handful of updates is enough to fill it
    # and make `nixos-rebuild` fail halfway through. Keep a bounded window.
    loader.systemd-boot.configurationLimit = 5;

    kernelParams = [
      "appledrm.show_notch=1"
    ];
  };

  hardware.asahi = {
    enable = true;
    setupAsahiSound = true;
    peripheralFirmwareDirectory = inputs.asahi-firmware;
  };

  # 没有这行时系统跑在 UTC，DMS 的时钟、日程和夜间模式的日出日落都会错位。
  time.timeZone = "Australia/Melbourne";

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  nix = {
    settings = {
      experimental-features = [
        "flakes"
        "nix-command"
      ];
    };

    # Nothing here reclaims disk on its own, and the ESP budget above depends on
    # old generations actually going away.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
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
