{ lib, pkgs, ... }:
let
  display = import ./display.nix { };

  # noctalia 的 alacritty 模板只写 themes/noctalia.toml（随壁纸/主题切换重写）。
  # 它的 apply.sh 会想往 alacritty.toml 里补一行 import，而这个文件是 home-manager
  # 管的只读软链 —— 写不进去就会让 post_hook 每次换主题都报错。所以这里先把同一
  # 个路径写好：apply.sh 的 `grep -q noctalia\.toml` 命中，生成的内容和现有文件
  # 逐字节相同，cmp 之后它什么都不写。静态配置声明式，动态配色留给 noctalia。
  # 窗口装饰不在这里关：niri 的 prefer-no-csd 已全局生效。
  alacrittyConfig = (pkgs.formats.toml { }).generate "alacritty.toml" {
    general.import = [ "~/.config/alacritty/themes/noctalia.toml" ];
  };

  # voxtype（语音输入，包在 gui.nix）的声明式配置。audio 三项和 output.mode 是
  # serde 必填字段（config.rs 里没挂 #[serde(default)]），写的就是上游模板的默认
  # 值，少一个都会解析失败；其余没写的键才真正取默认值。
  voxtypeConfig = (pkgs.formats.toml { }).generate "voxtype-config.toml" {
    hotkey = {
      # 按住说话（push_to_talk 是默认 mode），绑到 F5 听写键：内置键盘
      # （Apple MTP keyboard）把它上报为 KEY_MICMUTE(248)。voxtype 的按键名
      # 白名单里没有 MICMUTE，用 EVTEST_ 前缀直接给内核键码。对应的
      # XF86AudioMicMute 绑定已从 niri/config.kdl 移除，免得录音时静音麦克风。
      key = "EVTEST_248";
      modifiers = [ ];
    };
    audio = {
      device = "default";
      sample_rate = 16000;
      max_duration_secs = 60;
    };
    output.mode = "type";
    # 不要录音波形 OSD，且必须显式关：上游默认 enabled = true，daemon 会反复
    # spawn voxtype-osd，而这个构建里唯一的前端（quickshell）需要 PATH 上有
    # 裸的 `qs`——那意味着 1.2 GB 的 Qt6 闭包，不值得。
    osd.enabled = false;
    whisper = {
      # 多语言模型；模型文件不声明式管理，需要 `voxtype setup model` 下载到
      # ~/.local/share/voxtype/models（缺文件时 daemon 启动报错，不会自动下）。
      model = "large-v3-turbo";
      # 数组形式是受限自动检测：只在中/英之间判语种，短句不会误判成别的语言。
      language = [
        "zh"
        "en"
      ];
    };
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

        xdg.configFile."voxtype/config.toml".source = voxtypeConfig;

        # voxtype 上游只有 `voxtype setup systemd` 的命令式安装，这里照着它生成的
        # unit（src/setup/systemd.rs）声明同样的内容。挂 graphical-session.target：
        # wtype 注入文字要 WAYLAND_DISPLAY，niri-session 会把它导进 systemd 用户环境
        # （noctalia 的 service 同一个前提）。
        systemd.user.services.voxtype = {
          Unit = {
            Description = "voxtype push-to-talk voice-to-text daemon";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe pkgs.voxtype-vulkan} daemon";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # 桌面 shell。声明式默认值写在 ~/.config/noctalia/config.toml（store 里的
        # 只读软链），运行时在设置界面改的东西落到 ~/.local/state/noctalia/
        # settings.toml，两层不互相覆盖 —— 正是原来那段 jq + marker 播种脚本手搓
        # 出来的语义（已随 DMS 一起删掉）。checkConfig 默认开着，build 时会跑
        # `noctalia config validate`，
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

        # Noctalia owns the mutable gtk.css files. With only iconTheme set,
        # Home Manager writes settings.ini but does not declare gtk.css, so
        # dynamic palette changes remain writable.
        gtk = {
          enable = true;
          iconTheme = {
            package = pkgs.adwaita-icon-theme;
            name = "Adwaita";
          };
        };

        # Noctalia's Qt template only writes the palette, and Home Manager has
        # no standalone Qt icon-theme option. Seed qt5ct/qt6ct once instead.
        home.activation.iconTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          marker="$HOME/.local/state/nixcfg/.icon-theme-adwaita"

          if [ ! -e "$marker" ]; then
            mkdir -p "$(dirname "$marker")"

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
