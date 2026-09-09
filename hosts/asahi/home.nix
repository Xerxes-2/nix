{ lib, pkgs, ... }:
let
  display = import ./display.nix { inherit lib; };

  dmsSettings = (pkgs.formats.json { }).generate "settings.json" (
    import ./dms/settings.nix { inherit display; }
  );

  # noctalia 的 alacritty 模板只写 themes/noctalia.toml（随壁纸/主题切换重写）。
  # 它的 apply.sh 会想往 alacritty.toml 里补一行 import，而这个文件是 home-manager
  # 管的只读软链 —— 写不进去就会让 post_hook 每次换主题都报错。所以这里先把同一
  # 个路径写好：apply.sh 的 `grep -q noctalia\.toml` 命中，生成的内容和现有文件
  # 逐字节相同，cmp 之后它什么都不写。静态配置声明式，动态配色留给 noctalia。
  # 窗口装饰不在这里关：niri 的 prefer-no-csd 已全局生效。
  alacrittyConfig = (pkgs.formats.toml { }).generate "alacritty.toml" {
    general.import = [ "~/.config/alacritty/themes/noctalia.toml" ];
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
        # the noctalia integration applied (launcher, control center, lock,
        # audio, brightness and media keys go through `noctalia msg`, no waybar
        # autostart). The output scale comes from display.nix, which also sizes
        # the bar's notch spacer.
        xdg.configFile."niri/config.kdl".source = pkgs.replaceVars ./niri/config.kdl {
          scale = display.scaleText;
          xwaylandSatellite = lib.getExe pkgs.xwayland-satellite;
        };

        xdg.configFile."alacritty/alacritty.toml".source = alacrittyConfig;

        # 桌面 shell。声明式默认值写在 ~/.config/noctalia/config.toml（store 里的
        # 只读软链），运行时在设置界面改的东西落到 ~/.local/state/noctalia/
        # settings.toml，两层不互相覆盖 —— 正是下面那段 jq 播种脚本当年手搓出来
        # 的语义。checkConfig 默认开着，build 时跑 `noctalia config validate`，
        # 键名写错是构建失败，而不是运行时静默漂移。
        programs.noctalia = {
          enable = true;
          systemd.enable = true;

          settings = {
            shell = {
              font_family = "Inter";
              # DMS 自带 polkit agent；换掉之后这台机器上再没有别的了。
              polkit_agent = true;
            };

            theme = {
              mode = "dark";
              # 跟着壁纸生成配色，等价于原来 DMS 那套 matugen。
              source = "wallpaper";

              # bar 盖住 notch 的唯一办法。v5 的 bar 只有 background_opacity，
              # 没有单独的背景色：底色一律取 ColorRole::Surface（bar.cpp 的
              # applyBackgroundPalette）。pure_black_dark 把整条 surface 阶梯
              # 下移到 surface 落在 tone 0，也就是正黑，于是不透明的 bar 和
              # 物理 notch 连成一片。代价是所有暗色面板一起变纯黑，不只是 bar。
              pure_black_dark = true;

              # 内置模板接管原来 DMS 负责写的那几个文件：alacritty 配色、niri
              # 的焦点环/边框颜色（取代 dms/colors.kdl）、GTK 和 Qt 调色板。
              templates = {
                enable_builtin_templates = true;
                builtin_ids = [
                  "alacritty"
                  "niri"
                  "gtk3"
                  "gtk4"
                  "qt"
                ];
              };
            };

            # 天气和夜灯的日出日落都从这里取坐标。auto_locate 走 IP 定位，和原来
            # geoclue 的 [ip] 源做的是同一件事（换了个第三方：noctalia.dev）。
            # 不想要这次查询就删掉它，改写死 latitude/longitude。
            location.auto_locate = true;

            # 夜灯仍然走 wlr-gamma-control，所以前提照旧是 gui.nix 里那个打了
            # software-gamma 补丁的 niri。
            nightlight = {
              enabled = true;
              temperature_night = 4000;
            };

            # notch 那条 bar：不透明、无圆角、贴边、厚度正好盖住 notch，中间用
            # 一个定长 spacer 把 widget 从 notch 底下推开。thickness 和 length
            # 都是屏幕像素，直接来自 display.nix，没有要跟上游对齐的公式。
            bar.main = {
              position = "top";
              thickness = display.barThickness;
              background_opacity = 1.0;
              radius = 0;
              margin_ends = 0;
              margin_edge = 0;
              shadow = false;
              reserve_space = true;

              start = [
                "launcher"
                "workspaces"
                "active_window"
                "media"
              ];
              center = [ "notch" ];
              end = [
                "clock"
                "tray"
                "clipboard"
                "cpu"
                "ram"
                "notifications"
                "battery"
                "control-center"
              ];
            };

            # 名字等于类型的 widget 会自动实例化，其余的在这里定义。sysmon 一个
            # 实例只显示一项，所以 DMS 的 cpuUsage + memUsage 在这里是两个。
            widget = {
              notch = {
                type = "spacer";
                length = display.spacerSize;
              };
              cpu = {
                type = "sysmon";
                stat = "cpu_usage";
              };
              ram = {
                type = "sysmon";
                stat = "ram_pct";
              };
            };
          };
        };

        # 现在只剩 dms-greeter 在读这个文件：shell 已经换成 noctalia，而登录界面
        # 自己不画 bar，所以这里播的 bar 布局其实已经没人看，留着是因为 greeter
        # 还要从同一个 settings.json 取主题和图标主题。
        #
        # TODO revisit: 等 gui.nix 里的 greeter 换成 noctalia-greeter
        #   check: ls ~/.local/state/DankMaterialShell/.notch-layout-v4
        #   then:  整段连同 hosts/asahi/dms/ 和 display.nix 里的 innerPadding
        #          一起删掉
        #   last:  2026-08，asahi 上已应用（marker 在，所以这段现在是空转的）
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
