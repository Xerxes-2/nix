{
  description = "ubuntu 服务器的 CLI 工具集（声明式包管理）";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs-unstable, ... }:
    let
      system = "aarch64-linux";
      # claude-code 是 unfree 许可证,需要显式放行
      nixpkgsConfig = {
        allowUnfreePredicate = pkg: builtins.elem (nixpkgs-unstable.lib.getName pkg) [
          "claude-code"
        ];
      };
      pkgs = import nixpkgs-unstable { inherit system; config = nixpkgsConfig; };
    in
    {
      packages.${system}.default = pkgs.buildEnv {
        name = "Default packages";
        paths = with pkgs; [
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
          wakatime-cli
          yazi
          zellij
        ];
      };
    };
}
