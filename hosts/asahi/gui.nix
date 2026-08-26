{ pkgs, ... }:
{
  # Wayland compositor + desktop shell.
  programs.niri.enable = true;
  programs.dms-shell.enable = true;

  # DMS login screen running inside niri.
  services.displayManager = {
    defaultSession = "niri";
    dms-greeter = {
      enable = true;
      compositor.name = "niri";
      configHome = "/home/xerxes2";
    };
  };

  # Desktop plumbing.
  services.dbus.enable = true;
  services.gvfs.enable = true;
  services.libinput.enable = true;
  security.polkit.enable = true;
  xdg.mime.enable = true;

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
    alacritty
    brightnessctl
    firefox
    fuzzel
    grim
    nautilus
    networkmanagerapplet
    pavucontrol
    playerctl
    slurp
    swappy
    wl-clipboard
    xdg-utils
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
