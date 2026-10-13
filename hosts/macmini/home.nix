# xerxes2 的 Home Manager 配置：只用共享 CLI 工具集。
{ ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "pre-hm";

  home-manager.users.xerxes2 = {
    imports = [ ../../modules/home/cli.nix ];
    # 这台从 cachyos 远程推，本机没有仓库副本；NH_FLAKE 指过去只会报找不到。
    programs.nh.flake = null;
    home.stateVersion = "26.11";
  };
}
