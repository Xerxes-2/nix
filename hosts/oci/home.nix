# ubuntu 用户的 Home Manager 配置：共享 CLI 工具集 + 本机（Linux/btrfs）特有工具。
{ ... }:
{
  home-manager.users.ubuntu = { pkgs, ... }: {
    imports = [ ../../modules/home/cli.nix ];
    home.packages = with pkgs; [
      btdu # btrfs 专用，Linux only
    ];
  };
}
