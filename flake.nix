{
  description = "ubuntu 服务器的 CLI 工具集（声明式包管理）";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*.tar.gz";
    # 钉到已装的 commit，避免本地重新编译（升级时改成新 commit 或去掉 rev）
    herdr.url = "github:ogulcancelik/herdr/2bc1724c2dae72184a5d2ec070e30c70dc519f9b";
  };

  outputs = { self, nixpkgs, herdr }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.buildEnv {
        name = "my-tools";
        paths = with pkgs; [
          # 文件 / 搜索
          bat
          fd
          sd
          yazi

          # 系统 / 监控
          btdu
          procs
          viddy

          # 开发
          codex
          jujutsu
          nodejs
          pnpm
          powershell
          steel
          uv

          # 网络 / 安全
          osv-scanner
          steelix

          # 其他
          nix-index
          tldr
          wakatime-cli
          zellij

          # 第三方 flake
          herdr.packages.${system}.default
        ];
      };
    };
}
