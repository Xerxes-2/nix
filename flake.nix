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
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.home-manager.follows = "home-manager";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    # btrfs 实际占用核算（压缩 / reflink / 部分覆盖的 extent 都算进去），
    # 不在 nixpkgs 里。两台 NixOS 机器都用，见 modules/btrfs-tools.nix。
    xsz = {
      url = "github:SaltyKitkat/xsz";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs-unstable,
      home-manager,
      sops-nix,
      nix-darwin,
      determinate,
      ...
    }@inputs:
    let
      system = "aarch64-linux";
    in
    {

      # `nix run /etc/nixos#update` —— 更新 flake.lock 并自动把"更新了什么"写进提交
      # 信息。两台 NixOS 机器和 macOS 侧都可能跑，所以两个平台都给。
      apps = nixpkgs-unstable.lib.genAttrs [ "aarch64-linux" "aarch64-darwin" ] (
        sys:
        let
          pkgs = nixpkgs-unstable.legacyPackages.${sys};
        in
        {
          update = {
            type = "app";
            program = pkgs.lib.getExe (
              pkgs.writeShellApplication {
                name = "flake-update";
                # jq 解析 lock，jujutsu 提交，coreutils 保证 macOS 上也是 GNU date
                runtimeInputs = with pkgs; [
                  coreutils
                  jq
                  jujutsu
                ];
                text = builtins.readFile ./scripts/flake-update.sh;
              }
            );
          };
        }
      );

      nixosConfigurations.oci = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
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
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/unfree.nix
          ./hosts/asahi/configuration.nix
          ./hosts/asahi/home.nix
        ];
      };

      # MacBook（Apple Silicon，Determinate Nix）：macOS 侧，nix-darwin 接管，
      # Home Manager 作为其模块运行（曾是 standalone home-manager 入口）。
      # 使用：sudo darwin-rebuild switch --flake ~/.config/nix
      darwinConfigurations."XueMacBook-Pro" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit self; };
        modules = [
          determinate.darwinModules.default
          home-manager.darwinModules.home-manager
          ./modules/unfree.nix
          ./hosts/darwin/configuration.nix
          ./hosts/darwin/home.nix
        ];
      };
    };
}
