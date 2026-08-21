{
  description = "OCI 服务器 NixOS 系统配置（含用户工具集，via Home Manager）";

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
    };
}
