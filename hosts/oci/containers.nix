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
          dufs = {
            autoStart = true;
            unitConfig.Description = "dufs file server";
            serviceConfig = {
              Restart = "on-failure";
              TimeoutStopSec = "70";
            };
            containerConfig = {
              image = "docker.io/sigoden/dufs:latest";
              name = "dufs";
              autoUpdate = "registry";
              publishPorts = [ "127.0.0.1:5000:5000" ];
              volumes = [
                "${home}/.config/dufs/config.yaml:/config.yaml:ro"
                "${home}/dufs-data:/data:rw"
              ];
              exec = "-c /config.yaml";
            };
          };

          sillytavern = {
            autoStart = true;
            unitConfig.Description = "SillyTavern LLM frontend";
            serviceConfig = {
              Restart = "always";
              TimeoutStartSec = "120";
            };
            containerConfig = {
              image = "ghcr.io/sillytavern/sillytavern:latest";
              name = "sillytavern";
              autoUpdate = "registry";
              networks = [ "host" ];
              environments = {
                PUID = "1001";
                PGID = "1001";
              };
              volumes = [
                "${home}/sillytavern-data/config:/home/node/app/config:rw,U"
                "${home}/sillytavern-data/data:/home/node/app/data:rw,U"
                "${home}/sillytavern-data/plugins:/home/node/app/plugins:rw,U"
                "${home}/sillytavern-data/extensions:/home/node/app/public/scripts/extensions/third-party:rw,U"
              ];
            };
          };

        };
      };
    };
}
