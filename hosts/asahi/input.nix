{ pkgs, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";

    fcitx5 = {
      # Niri supports the native Wayland input-method protocol.
      waylandFrontend = true;
      addons = with pkgs; [
        fcitx5-gtk
        fcitx5-rime
        qt6Packages.fcitx5-chinese-addons
      ];

      # English plus Chinese Shuangpin using Microsoft's layout.
      settings = {
        inputMethod = {
          GroupOrder."0" = "Default";
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us";
            DefaultIM = "shuangpin";
          };
          "Groups/0/Items/0" = {
            Name = "keyboard-us";
            Layout = "";
          };
          "Groups/0/Items/1" = {
            Name = "shuangpin";
            Layout = "";
          };
        };
        addons.pinyin.globalSection.ShuangpinProfile = "MS";
      };
    };
  };

  environment.sessionVariables = {
    # Prefer native Wayland in Electron apps and let modern Qt fall back to the
    # Fcitx module if its Wayland text-input implementation is insufficient.
    NIXOS_OZONE_WL = "1";
    QT_IM_MODULES = "wayland;fcitx";
  };

  # GUI for changing the Shuangpin layout or other Fcitx settings.
  environment.systemPackages = [ pkgs.qt6Packages.fcitx5-configtool ];
}
