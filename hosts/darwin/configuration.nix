# macOS 侧（同一台 14" MacBook Pro，与 asahi 双启动）的 nix-darwin 系统配置。
# 跨机器共享的 CLI 工具在 modules/home/cli.nix（经 home.nix 的 HM 模块引入），
# 这里只放系统级的东西：GUI 应用、字体、homebrew、macOS defaults。
{ pkgs, self, ... }:

{
  # ── Nix ────────────────────────────────────────────────────────
  # Determinate 模块接管 nix-daemon；替代裸的 nix.enable = false
  determinateNix.enable = true;
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 5;
  system.primaryUser = "xerxes2";

  # ── User ───────────────────────────────────────────────────────
  users.users.xerxes2 = {
    name = "xerxes2";
    home = "/Users/xerxes2";
  };

  # ── System packages ────────────────────────────────────────────
  # 只放 GUI 应用和系统级工具；CLI 工具在 modules/home/cli.nix（共享）
  # 或 hosts/darwin/home.nix（darwin 特有）。
  environment.systemPackages = with pkgs; [
    container # Apple's container CLI
    mas

    # --- GUI apps migrated from brew casks ---
    iina
    inkscape
    keka
    localsend
    wireshark
    zerotierone

    # NOTE: zed-editor builds from source (very slow on macOS).
    # Keep the brew cask "zed" instead.
  ];

  # ── Fonts ──────────────────────────────────────────────────────
  # 装到 /Library/Fonts/Nix Fonts。
  # 留在 homebrew 的：comic-sans-ms, consolas-for-powerline,
  # hackgen-nerd, linux-libertine（专有 / nixpkgs 没有）
  fonts.packages = with pkgs; [
    nerd-fonts.caskaydia-cove
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.meslo-lg
    nerd-fonts.monaspace
    font-awesome
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts
  ];

  # ── Homebrew ───────────────────────────────────────────────────
  # nix-darwin 由这些列表生成 Brewfile 并跑 brew bundle。
  # cleanup = "uninstall"：不在列表里的 brew 包会被卸载。
  homebrew = {
    enable = true;
    user = "xerxes2";
    prefix = "/opt/homebrew";

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall";
    };

    # ── Taps ──
    taps = [
      {
        name = "j-x-z/tap";
        trusted = true;
      }
      {
        name = "jorgelbg/tap";
        trusted = true;
      }
      {
        name = "italomandara/cxpatcher";
        trusted = true;
      }
      {
        name = "badabing2005/pixelflasher";
        trusted = true;
      }
      {
        name = "brewforge/extras";
        trusted = true;
      }
    ];

    # ── Brews (formulae not in nixpkgs) ──
    brews = [
      "pkg-config-wrapper"
      "j-x-z/tap/cocoa-way"
      "j-x-z/tap/waypipe-darwin"
      "jorgelbg/tap/pinentry-touchid"
    ];

    # ── Casks (only what can't migrate to nixpkgs) ──
    # NOTE: Already migrated to nixpkgs:
    #   claude-code, codex, iina, inkscape, keka, localsend,
    #   wireshark, zerotier-one
    casks = [
      "brewforge/extras/mxiris-lyricsx" # 曾名 lyricsx-mxiris
      "italomandara/cxpatcher/cxpatcher"
      "badabing2005/pixelflasher/pixelflasher"

      # --- display / input ---
      "betterdisplay"
      "keycastr"
      "keyclu"
      "mos"

      # --- audio ---
      "blackhole-2ch"

      # --- browsers / desktop (linux-only in nixpkgs) ---
      "ghostty"
      "ungoogled-chromium"
      "zen"
      "zed"
      "discord"

      # --- chat / comms ---
      "lark"
      "microsoft-teams"
      "telegram"
      "tencent-meeting"
      "wechat"
      "zoom"

      # --- cloud / sync ---
      "binance"
      "google-drive"
      "bitwarden"

      # --- code / dev (desktop apps, separate from their CLI counterparts) ---
      "claude" # Claude desktop (claude-code CLI is in nixpkgs)
      "codex-app" # Codex desktop (codex CLI is in nixpkgs)

      # --- crossover ---
      "crossover"
      "gstreamer-runtime"

      # --- file transfer ---
      "openmtp"

      # --- gaming (linux-only in nixpkgs) ---
      "steam"
      "steamcmd"

      # --- media ---
      "handbrake-app"
      "obs"
      "macwhisper"
      "moonlight"
      "stats"

      # --- network ---
      "cloudflare-warp"
      "tailscale-app" # 曾名 tailscale（cask；同名 formula 是 CLI）

      # --- runtimes (linux-only in nixpkgs) ---
      "nwjs"

      # --- qmk / android ---
      "qmk-toolbox"

      # --- system utils ---
      "jordanbaird-ice"
      "playcover-community"

      # --- torrent ---
      "c0re100-qbittorrent"

      # --- fonts (proprietary / not in nixpkgs) ---
      "font-comic-sans-ms"
      "font-consolas-for-powerline"
      "font-hackgen-nerd"
      "font-linux-libertine"
    ];
  };

  # ── Shell ──────────────────────────────────────────────────────
  # 系统层 enable 负责写 /etc/shells 和 vendor 补全；
  # 用户配置（插件、alias）在 home.nix 的 HM 模块里。
  programs.fish.enable = true;
  programs.zsh.enable = true;

  # ── macOS preferences ──────────────────────────────────────────
  system.defaults = {

    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "Nlsv"; # list view
      ShowPathbar = true;
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
    };

    trackpad = {
      Clicking = false; # 轻按即点击：关
      TrackpadThreeFingerDrag = true;
    };
  };

  # 关掉开盖即开机（%01 = 仅禁止开盖启动；接电源仍会开机，
  # 若两者都禁止改成 "%00"）
  system.nvram.variables."BootPreference" = "%01";

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;
}
