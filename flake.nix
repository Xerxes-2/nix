{
  description = "多机 Nix 配置：NixOS 服务器 + 其他装有 Nix 的机器";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
  };

  outputs = { self, nixpkgs-unstable, home-manager, quadlet-nix, ... }:
    let
      system = "aarch64-linux";
    in
    {

      nixosConfigurations.oci = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit quadlet-nix; };
        modules = [
          quadlet-nix.nixosModules.quadlet
          home-manager.nixosModules.home-manager
          ./hosts/oci/configuration.nix
          ./hosts/oci/home.nix
          ./hosts/oci/containers.nix
        ];
      };

      # 主机名别名：本机上 `nixos-rebuild switch --flake ~/nixcfg` 可省略 #oci
      nixosConfigurations."instance-20260821-1942" = self.nixosConfigurations.oci;

      # 其他机器（如 MacBook，standalone home-manager）在此追加：
      # homeConfigurations."<user>@<host>" = home-manager.lib.homeManagerConfiguration { ... };
    };
}
