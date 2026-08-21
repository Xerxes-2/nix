{
  description = "OCI 服务器：CLI 工具集（声明式包管理）+ NixOS 系统配置";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
  };

  outputs = { nixpkgs-unstable, home-manager, quadlet-nix, ... }:
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
          vscode-json-languageserver
          wakatime-cli
          yazi
          zellij
        ];
      };

      nixosConfigurations.oci = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit quadlet-nix; };
        modules = [
          quadlet-nix.nixosModules.quadlet
          home-manager.nixosModules.home-manager
          ./hosts/oci/configuration.nix
          ./hosts/oci/containers.nix
        ];
      };
    };
}
