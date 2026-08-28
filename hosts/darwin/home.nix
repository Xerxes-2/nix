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
          jq
          nushell

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
            {
              name = "tide";
              src = tide.src;
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

          shellInit = ''
            # carapace completions
            carapace _carapace 2>/dev/null
          '';

          interactiveShellInit = ''
            starship init fish | source
            zoxide init fish | source
            fzf --fish | source
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
          settings = {
            "*" = {
              AddKeysToAgent = "yes";
              IdentityFile = "~/.ssh/id_ed25519";
              UseKeychain = "yes";
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
