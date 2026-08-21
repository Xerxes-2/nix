# rootless podman 容器（quadlet-nix via home-manager）
# 由原 ~/.config/containers/systemd/*.container 逐字段翻译而来。
# 注意：首次 HM 激活前需把旧的 dufs/sillytavern/wakapi.container 移走，
# 已设 backupFileExtension 兜底。
{ quadlet-nix, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "pre-hm";

  home-manager.users.ubuntu = { config, ... }:
    let
      home = config.home.homeDirectory; # /home/ubuntu
    in
    {
      imports = [ quadlet-nix.homeManagerModules.quadlet ];

      home.stateVersion = "26.05";

      virtualisation.quadlet = {
        autoEscape = true;
        autoUpdate.enable = true; # 对应原 podman-auto-update.timer

        containers = {


        };
      };
    };
}
