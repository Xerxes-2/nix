{
  description = "ubuntu 服务器的 CLI 工具集（声明式包管理）";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*.tar.gz";
    # 仅供 herdr 使用（weekly 还没收录；官方缓存有 aarch64 成品，免编译）
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.buildEnv {
        name = "my-tools";
        paths = with pkgs; [
          nixd
          nixfmt
          bat
          fd
          sd
          yazi
          btdu
          procs
          viddy
          codex
          jujutsu
          nodejs
          pnpm
          powershell
          steel
          uv
          osv-scanner
          steelix
          nix-index
          tldr
          wakatime-cli
          zellij

          # 来自 unstable（weekly 收录后可改回 pkgs.herdr 并删掉 unstable 输入）
          pkgsUnstable.herdr
        ];
      };
    };
}
