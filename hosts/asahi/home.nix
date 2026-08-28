{ lib, pkgs, ... }:
let
  display = import ./display.nix { inherit lib; };

  dmsSettings = (pkgs.formats.json { }).generate "settings.json" (
    import ./dms/settings.nix { inherit display; }
  );

  # DMS 的 matugen 模板只生成 dank-theme.toml（随壁纸/主题切换重写），
  # 从不接管 alacritty.toml。所以静态配置交给 home-manager 声明式管理，
  # 动态配色留给 DMS 在运行时写，两者互不覆盖。
  # 窗口装饰不在这里关：niri 的 prefer-no-csd 已全局生效。
  alacrittyConfig = (pkgs.formats.toml { }).generate "alacritty.toml" {
    general.import = [ "~/.config/alacritty/dank-theme.toml" ];
  };
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # niri writes a default config.kdl on first start; keep that copy around
    # when home-manager takes the file over.
    backupFileExtension = "hm-backup";

    users.xerxes2 =
      { lib, pkgs, ... }:
      {
        imports = [
          ../../modules/home/cli.nix
          ../../modules/home/brightness.nix
        ];

        programs.home-manager.enable = true;

        # niri's config is fully declarative: it is the upstream template with
        # the DMS integration applied (DMS launcher, lock screen, audio,
        # brightness and media keys go through `dms ipc`, no waybar autostart).
        # The output scale comes from display.nix, which also sizes the DMS
        # notch spacer.
        xdg.configFile."niri/config.kdl".source = pkgs.replaceVars ./niri/config.kdl {
          scale = display.scaleText;
          xwaylandSatellite = lib.getExe pkgs.xwayland-satellite;
        };

        xdg.configFile."alacritty/alacritty.toml".source = alacrittyConfig;

        # Seed the notch-aware DMS bar layout. This is a one-time migration:
        # DMS owns settings.json at runtime, so later UI changes stay.
        #
        # TODO revisit: 改布局或 DMS 换 config 版本时 —— 有 marker 的机器上这段
        # 是空转的
        #   check: ls ~/.local/state/DankMaterialShell/.notch-layout-v4
        #   then:  要重新播种就把 marker 改成 -v5；等所有机器都迁完之后，可以只
        #          留 else 分支（全新安装用）并删掉 jq 合并那一半
        #   last:  2026-08，asahi 上已应用
        home.activation.dmsNotchLayout = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          settings="$HOME/.config/DankMaterialShell/settings.json"
          marker="$HOME/.local/state/DankMaterialShell/.notch-layout-v4"

          if [ ! -e "$marker" ]; then
            mkdir -p "$(dirname "$settings")" "$(dirname "$marker")"
            if [ -s "$settings" ] && ${pkgs.jq}/bin/jq -e '.barConfigs | type == "array" and length > 0' "$settings" >/dev/null; then
              tmp="$(mktemp)"
              ${pkgs.jq}/bin/jq '
                .iconThemeDark = "Adwaita"
                | .iconThemeLight = "Adwaita"
                | .barConfigs[0].position = 0
                | .barConfigs[0].spacing = 0
                | .barConfigs[0].innerPadding = ${toString display.innerPadding}
                | .barConfigs[0].bottomGap = 0
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
                    { "id": "spacer", "size": ${toString display.spacerSize} }
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
              install -m 0600 ${dmsSettings} "$settings"
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
