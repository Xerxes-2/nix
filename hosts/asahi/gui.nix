{ inputs, pkgs, ... }:
let
  # DMS currently has no per-bar background-color setting. Add one while
  # preserving its normal themed background as the fallback.
  dmsShell = pkgs.dms-shell.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      substituteInPlace $out/share/quickshell/dms/Modules/DankBar/DankBarWindow.qml \
        --replace-fail \
          'readonly property color _surfaceContainer: Theme.surfaceContainer' \
          'readonly property color _surfaceContainer: barConfig?.backgroundColor ?? Theme.surfaceContainer'
    '';
  });
in
{
  # Wayland compositor + desktop shell.
  programs.niri.enable = true;
  programs.dms-shell = {
    enable = true;
    package = dmsShell;
  };

  # Give Qt applications (including DMS/Quickshell) a real platform theme so
  # named system-tray icons are resolved through the selected icon theme.
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  # DMS login screen running inside niri.
  services.displayManager = {
    defaultSession = "niri";
    dms-greeter = {
      enable = true;
      compositor.name = "niri";
      configHome = "/home/xerxes2";
      configFiles = [ ./dms/settings.json ];
    };
  };

  # Desktop plumbing.
  services.dbus.enable = true;
  services.gvfs.enable = true;
  services.libinput.enable = true;
  security.polkit.enable = true;
  xdg.mime.enable = true;

  # System services the DMS widgets talk to directly.
  # Without UPower the battery widget/popout has no data at all.
  services.upower.enable = true;

  # DMS ships its own Bluetooth UI on top of BlueZ.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # Location source for the weather widget and the night-mode schedule.
  # DMS falls back to IP geolocation when GeoClue has no fix yet.
  services.geoclue2 = {
    enable = true;
    appConfig.dms = {
      isAllowed = true;
      isSystem = true;
      users = [ "1000" ];
    };
  };

  # Audio stack.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Useful GUI/session tools.
  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    alacritty
    firefox
    nautilus
    pavucontrol
    # `pactl` only; DMS uses it to switch Bluetooth audio card profiles.
    pulseaudio
    # Optional DMS screenshot editor (`dms ipc call niri screenshot`).
    swappy
    telegram-desktop
    vesktop # Discord client; official Discord has no aarch64-linux build.
    wl-clipboard
    xdg-utils
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  fonts.packages = with pkgs; [
    fira-code
    inter
    material-symbols
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
}
