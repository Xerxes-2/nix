# ubuntu 用户的 Home Manager 配置：共享 CLI 工具集 + 本机（Linux/btrfs）特有工具。
{ ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "pre-hm";

  home-manager.users.ubuntu = { pkgs, ... }: {
    imports = [ ../../modules/home/cli.nix ];
    home.stateVersion = "26.05";

    # dufs 文件服务器（从 rootless 容器迁入，2026-08）。
    # 配置含 auth 凭据，故 ~/.config/dufs/config.yaml 不纳管、不进 git；
    # 其中 bind: 127.0.0.1（容器时代靠 publish 限制，原生靠配置）。
    systemd.user.services.dufs = {
      Unit.Description = "dufs file server";
      Service = {
        ExecStart = "${pkgs.dufs}/bin/dufs --config %h/.config/dufs/config.yaml";
        Restart = "always";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
