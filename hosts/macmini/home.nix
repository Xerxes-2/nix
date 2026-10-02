# xerxes2 的 Home Manager 配置：只用共享 CLI 工具集。
{ ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "pre-hm";

  home-manager.users.xerxes2 = {
    imports = [ ../../modules/home/cli.nix ];
    home.stateVersion = "26.11";
  };
}
