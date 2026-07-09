{
  description = "ubuntu 服务器的 CLI 工具集（声明式包管理）";

  inputs = {
    nixpkgs-weekly.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1";
  };

  outputs = { nixpkgs-weekly, ... }:
    let
      system = "aarch64-linux";
      # claude-code 是 unfree 许可证,需要显式放行
      nixpkgsConfig = {
        allowUnfreePredicate = pkg: builtins.elem (nixpkgs-weekly.lib.getName pkg) [
          "claude-code"
        ];
      };
      pkgs = import nixpkgs-weekly { inherit system; config = nixpkgsConfig; };
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
