# ubuntu 用户的 CLI 工具集（原 flake.nix packages.default buildEnv，
# 曾以 `nix profile install .#` 方式安装为 nixcfg profile，现统一走 HM，
# 随 nixos-rebuild switch 一起更新）。
{ ... }:
{
  home-manager.users.ubuntu = { pkgs, ... }: {
    home.packages = with pkgs; [
      bat
      btdu
      claude-code
      codex
      difftastic
      fd
      go
      herdr
      jjui
      jujutsu
      nixd
      nixfmt
      nix-index
      nodejs-slim
      osv-scanner
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
  };
}
