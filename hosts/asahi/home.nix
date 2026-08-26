{ ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.xerxes2 =
      { lib, pkgs, ... }:
      {
        imports = [ ../../modules/home/cli.nix ];

        programs.home-manager.enable = true;

        # Reserve the exact center for the 14-inch MacBook Pro notch. Keep DMS
        # widgets in edge-anchored groups so they flow inward from both sides.
        # This is a one-time migration; later UI changes remain mutable.
        home.activation.dmsNotchLayout = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          settings="$HOME/.config/DankMaterialShell/settings.json"
          marker="$HOME/.local/state/DankMaterialShell/.notch-layout-v3"

          if [ ! -e "$marker" ]; then
            mkdir -p "$(dirname "$settings")" "$(dirname "$marker")"
            if [ -s "$settings" ] && ${pkgs.jq}/bin/jq -e '.barConfigs | type == "array" and length > 0' "$settings" >/dev/null; then
              tmp="$(mktemp)"
              ${pkgs.jq}/bin/jq '
                .iconThemeDark = "Adwaita"
                | .iconThemeLight = "Adwaita"
                | .barConfigs[0].position = 0
                | .barConfigs[0].spacing = 0
                | .barConfigs[0].transparency = 1.0
                | .barConfigs[0].backgroundColor = "#000000"
                | .barConfigs[0].squareCorners = true
                | .barConfigs[0].leftWidgets = [
                    "launcherButton",
                    "workspaceSwitcher",
                    "focusedWindow",
                    "music"
                  ]
                | .barConfigs[0].centerWidgets = [
                    { "id": "spacer", "size": 220 }
                  ]
                | .barConfigs[0].rightWidgets = [
                    "clock",
                    "systemTray",
                    "clipboard",
                    "cpuUsage",
                    "memUsage",
                    "notificationButton",
                    "battery",
                    "controlCenterButton"
                  ]
              ' "$settings" > "$tmp"
              install -m 0600 "$tmp" "$settings"
              rm -f "$tmp"
            else
              install -m 0600 ${./dms/settings.json} "$settings"
            fi

            # DMS only applies these files when the theme is changed through
            # its UI, so initialize them explicitly for the first migration.
            for toolkit in gtk-3.0 gtk-4.0; do
              config_dir="$HOME/.config/$toolkit"
              config_file="$config_dir/settings.ini"
              mkdir -p "$config_dir"
              if [ -f "$config_file" ]; then
                if grep -q '^gtk-icon-theme-name=' "$config_file"; then
                  sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name=Adwaita/' "$config_file"
                elif grep -q '^\[Settings\]' "$config_file"; then
                  sed -i '/^\[Settings\]/a gtk-icon-theme-name=Adwaita' "$config_file"
                else
                  printf '\n[Settings]\ngtk-icon-theme-name=Adwaita\n' >> "$config_file"
                fi
              else
                printf '[Settings]\ngtk-icon-theme-name=Adwaita\n' > "$config_file"
              fi
            done

            for toolkit in qt5ct qt6ct; do
              config_dir="$HOME/.config/$toolkit"
              config_file="$config_dir/$toolkit.conf"
              mkdir -p "$config_dir"
              if [ -f "$config_file" ]; then
                if grep -q '^icon_theme=' "$config_file"; then
                  sed -i 's/^icon_theme=.*/icon_theme=Adwaita/' "$config_file"
                elif grep -q '^\[Appearance\]' "$config_file"; then
                  sed -i '/^\[Appearance\]/a icon_theme=Adwaita' "$config_file"
                else
                  printf '\n[Appearance]\nicon_theme=Adwaita\n' >> "$config_file"
                fi
              else
                printf '[Appearance]\nicon_theme=Adwaita\n' > "$config_file"
              fi
            done

            touch "$marker"
          fi
        '';

        home = {
          username = "xerxes2";
          homeDirectory = "/home/xerxes2";
          stateVersion = "25.05";
        };
      };
  };
}
