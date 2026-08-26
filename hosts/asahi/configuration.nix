{ inputs, pkgs, ... }:
{
  imports = [
    inputs.nixos-apple-silicon.nixosModules.default
    # Run `sudo nixos-generate-config --show-hardware-config | tee hardware-configuration.nix`
    # and uncomment this line.
    ./hardware-configuration.nix
    ./filesystems.nix
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

    # Run x86_64 Linux binaries through qemu-user. This is the general-purpose
    # escape hatch (one-off binaries, building x86 packages); the FEX + muvm
    # container in containers.nix is the fast path for anything that needs
    # real throughput, like games.
    binfmt.emulatedSystems = [ "x86_64-linux" ];
  };

  # Loader for binaries that were not built by Nix and expect an FHS-style
  # dynamic linker (npm/pip/cargo downloads, vendored SDK toolchains).
  programs.nix-ld.enable = true;

  # The panel is 3024x1964, which makes the default 8x16 console font unreadable
  # - relevant exactly when it hurts, i.e. when the graphical session is broken
  # and a VT is all that is left.
  console.font = "${pkgs.terminus_font}/share/consolefonts/ter-v32n.psf.gz";

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

      # 16G of unified memory shared with the GPU. Nix defaults to one job per
      # core (10 here), and a handful of parallel heavy builds is a reliable
      # way to hit the OOM killer. Cap the number of concurrent derivations
      # but leave `cores` at 0 (= all cores) so a single big build - the Asahi
      # kernel, which has no binary cache upstream - still uses the whole CPU.
      max-jobs = 2;
      cores = 0;
    };

    # Building should not make the desktop stutter: the daemon and its children
    # only get CPU and disk when nothing else wants them.
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";

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
