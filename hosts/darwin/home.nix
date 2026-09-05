# xerxes2 用户的 Home Manager（macOS 侧，作为 nix-darwin 模块运行）。
# 共享 CLI 工具集来自 modules/home/cli.nix；这里放 darwin 特有的包和
# shell / git / gpg 等用户级配置。
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # HM 接管 ~/.config/fish/config.fish 等文件时，把已存在的旧副本留个底。
    backupFileExtension = "hm-backup";

    users.xerxes2 =
      { pkgs, ... }:
      {
        imports = [ ../../modules/home/cli.nix ];

        programs.home-manager.enable = true;

        # HM 的 fish 模块默认开 man.generateCaches（给 fish 生成基于 man 页的补全），
        # 但新版 HM 在 darwin 上 man.package 默认 null（用系统 man），cache 无效且告警。
        programs.man.generateCaches = false;

        home = {
          username = "xerxes2";
          homeDirectory = "/Users/xerxes2";
          stateVersion = "26.05";
        };

        # ── darwin 特有的用户包（跨机器共享的在 cli.nix）──────────────
        home.packages = with pkgs; [
          # --- shell / terminal ---
          carapace
          croc
          nushell

          # --- GNU 版基础工具（macOS 自带的是 BSD 版）-------------------
          # agent 生成的脚本几乎都是 GNU 语法（`sed -i` 不带备份后缀、
          # `grep -P`、`find -printf`、`xargs -r`…），在 BSD 版上直接报错；
          # 而 /bin/bash 还停在 3.2（无关联数组、无 `${v,,}`）。装进
          # /etc/profiles/per-user/xerxes2/bin 后会 shadow /usr/bin 里的同名
          # 命令——这是有意的，交互使用上的差别可以忽略。
          bashInteractive
          findutils
          gawk
          gnugrep
          gnused

          # --- dev / scm ---
          android-tools
          chezmoi
          git-lfs
          hyperfine
          typst
          typstyle

          # --- network ---
          inetutils
          mosh
          nmap
          wakeonlan

          # --- crypto / security ---
          pwgen

          # --- media ---
          ffmpegthumbnailer
          gst_all_1.gstreamer
          scrcpy
          yt-dlp

          # --- language toolchains ---
          luajit
          protobuf
          rustup
          zig

          # --- custom / niche ---
          libimobiledevice
          payload-dumper-go
          tdl # brew: telegram-downloader
        ];

        # ── Fish ───────────────────────────────────────────────────────
        # 包本身由 cli.nix 的 programs.fish.enable 提供，这里加 darwin 侧的
        # 插件和 alias。
        programs.fish = {
          plugins = with pkgs.fishPlugins; [
            {
              name = "autopair";
              src = autopair.src;
            }
            {
              name = "done";
              src = done.src;
            }
          ];

          shellAliases = {
            ls = "eza";
            ll = "eza -l";
            la = "eza -la";
            tree = "eza --tree";
            cat = "bat";
            lg = "lazygit";
            jn = "jj new";
            jp = "jj git push";
            jl = "jj log";
          };

          interactiveShellInit = ''
            starship init fish | source
            zoxide init fish | source
            fzf --fish | source
            carapace _carapace fish 2>/dev/null | source
          '';
        };

        # ── Starship ───────────────────────────────────────────────────
        programs.starship = {
          enable = true;
          settings = {
            add_newline = false;
            format = "$all";
            character = {
              success_symbol = "[➜](bold green)";
              error_symbol = "[➜](bold red)";
            };
          };
        };

        # ── Git ────────────────────────────────────────────────────────
        programs.git = {
          enable = true;
          settings = {
            user = {
              name = "Xerxes-2";
              email = "dspxue@gmail.com";
              signingkey = "A6C508165D76B601";
            };
            commit.gpgsign = true;
            init.defaultBranch = "main";
            push.autoSetupRemote = true;
            pull.rebase = true;
            core.editor = "hx"; # helix
            core.autocrlf = "input";
          };
          lfs.enable = true;
          ignores = [
            ".DS_Store"
            "*.swp"
            ".direnv"
            ".devenv"
          ];
        };

        # ── Bat ────────────────────────────────────────────────────────
        programs.bat = {
          enable = true;
          config.theme = "gruvbox-dark";
        };

        # ── Zoxide ─────────────────────────────────────────────────────
        programs.zoxide = {
          enable = true;
          options = [ "--cmd=cd" ];
        };

        # ── Fzf ────────────────────────────────────────────────────────
        programs.fzf = {
          enable = true;
          defaultCommand = "fd --type f --strip-cwd-prefix";
          defaultOptions = [
            "--height 40%"
            "--layout reverse"
            "--border"
          ];
        };

        # ── Direnv ─────────────────────────────────────────────────────
        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
        };

        # ── SSH ────────────────────────────────────────────────────────
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          # 具体 Host 别名/IP 属于敏感信息，不进公开仓库，
          # 放本地未托管的 ~/.ssh/config.local（自行备份）。
          includes = [ "~/.ssh/config.local" ];
          settings = {
            "*" = {
              AddKeysToAgent = "yes";
              IdentityFile = "~/.ssh/id_ed25519";
              UseKeychain = "yes";
              ServerAliveInterval = 30;
              ServerAliveCountMax = 3;
              TCPKeepAlive = "yes";
            };
          };
        };

        # ── GPG ────────────────────────────────────────────────────────
        programs.gpg.enable = true;
        services.gpg-agent = {
          enable = true;
          defaultCacheTtl = 86400;
          maxCacheTtl = 86400;
          pinentry.package = pkgs.pinentry_mac;
          # Note: pinentry-touchid 在 homebrew（jorgelbg/tap），nixpkgs 没有。
        };

        # ── Session variables ──────────────────────────────────────────
        home.sessionVariables = {
          EDITOR = "hx";
          VISUAL = "hx";
          PAGER = "less";
          STEEL_SEARCH_PATHS = "${pkgs.steel}/share/steel/cogs"; # from brew caveats
        };
      };
  };
}
