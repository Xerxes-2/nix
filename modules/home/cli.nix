# 跨机器共享的 CLI 工具集（Home Manager 模块，Linux/macOS 通用）。
# 各 host 的 home.nix 导入此模块，平台特有工具在各自 host 里追加。
{ pkgs, ... }:
{
  # 登录 shell。真正把 fish 设为登录 shell 的是各系统层的
  # `programs.fish.enable`（NixOS 上还有 `users.users.<u>.shell`；darwin 上
  # nix-darwin 的同名选项负责写 /etc/shells 和 vendor 补全）。
  #
  # 这里开的是 HM 模块，管 ~/.config/fish/config.fish，让 HM 装的包和
  # home.sessionVariables 在 fish 里也生效。
  programs.fish.enable = true;

  home.packages = with pkgs; [
    bat
    btop
    claude-code
    codex
    curl
    difftastic
    eza
    fastfetch
    fd
    gh
    git
    go
    herdr
    htop
    jjui
    jujutsu
    lnav
    nano
    nixd
    nixfmt
    nix-index
    nodejs-slim
    osv-scanner
    pi-coding-agent
    pnpm
    powershell
    procs
    ripgrep
    rsync
    sd
    sqlite
    steel
    steelix
    tldr
    tokei
    tombi
    tree
    unar
    unzip
    uv
    viddy
    vim
    vscode-json-languageserver
    wakatime-cli
    wget
    yazi
    zellij
    zip
  ];
}
