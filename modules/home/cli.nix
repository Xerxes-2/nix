# 跨机器共享的 CLI 工具集（Home Manager 模块，Linux/macOS 通用）。
# 各 host 的 home.nix 导入此模块，平台特有工具在各自 host 里追加。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bat
    claude-code
    codex
    difftastic
    fd
    go
    gh
    herdr
    jjui
    jujutsu
    nixd
    nixfmt
    nix-index
    nodejs-slim
    osv-scanner
    pi-coding-agent
    pnpm
    powershell
    procs
    sd
    steel
    steelix
    tldr
    tombi
    uv
    viddy
    vscode-json-languageserver
    wakatime-cli
    yazi
    zellij
  ];
}
