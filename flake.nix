{
  description = "ubuntu 服务器的 CLI 工具集（声明式包管理）";

  inputs = {
    nixpkgs-weekly.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*.tar.gz";
    # 仅供 herdr 使用（weekly 还没收录；官方缓存有 aarch64 成品，免编译）
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs-weekly, nixpkgs-unstable, ... }:
    let
      system = "aarch64-linux";
      # claude-code 是 unfree 许可证,需要显式放行
      nixpkgsConfig = {
        allowUnfreePredicate = pkg: builtins.elem (nixpkgs-weekly.lib.getName pkg) [
          "claude-code"
        ];
      };
      pkgs = import nixpkgs-weekly { inherit system; config = nixpkgsConfig; };
      pkgsUnstable = import nixpkgs-unstable { inherit system; config = nixpkgsConfig; };
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
          jjui
          jujutsu
          nixd
          nixfmt
          nix-index
          nodejs
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

          # 来自 unstable（weekly 收录后可改回 pkgs.herdr 并删掉 unstable 输入）
          pkgsUnstable.herdr
        ];
      };
    };
}
