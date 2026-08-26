{
  description = "多机 Nix 配置：NixOS 服务器 + 其他装有 Nix 的机器";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    asahi-firmware = {
      url = "path:/boot/vendorfw";
      flake = false;
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs-unstable,
      home-manager,
      sops-nix,
      ...
    }@inputs:
    let
      system = "aarch64-linux";
    in
    {

      nixosConfigurations.oci = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
          ./modules/unfree.nix
          ./hosts/oci/configuration.nix
          ./hosts/oci/home.nix
        ];
      };

      # 主机名别名：本机上 `nixos-rebuild switch --flake ~/nixcfg` 可省略 #oci
      nixosConfigurations."instance-20260821-1942" = self.nixosConfigurations.oci;

      nixosConfigurations.asahi = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/asahi/configuration.nix ];
      };

      # MacBook（Apple Silicon，Determinate Nix）：standalone home-manager 入口。
      # 使用：nix run home-manager -- switch --flake ~/nixcfg#xerxes2
      # 如果某个共享包在 darwin 上不可用/不需要，在下面 home.nix 里排除即可。
      # 将来若想升级到 nix-darwin，这份 home 配置可原样挪进其 HM 模块。
      homeConfigurations."xerxes2" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs-unstable.legacyPackages.aarch64-darwin;
        modules = [
          ./modules/unfree.nix
          ./modules/home/cli.nix
          {
            home.username = "xerxes2";
            home.homeDirectory = "/Users/xerxes2";
            home.stateVersion = "26.05";
          }
        ];
      };
    };
}
