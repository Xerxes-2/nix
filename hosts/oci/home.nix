# ubuntu 用户的 Home Manager 配置：共享 CLI 工具集 + 本机（Linux/btrfs）特有工具。
{ inputs, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "pre-hm";

  home-manager.users.ubuntu = { pkgs, ... }: {
    imports = [
      ../../modules/home/cli.nix
      inputs.rex.homeManagerModules.default
    ];
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

    # Rex personal server，以 ubuntu 身份跑在 user service 里（会顺带打开 programs.rex）。
    # 没用 NixOS 模块：只有自己一个账户、远程走公网 ssh，
    # 不需要 login server 的身份映射和 Tailscale Serve，也就不用多跑一个 root 进程。
    # 共享服务器模式的会话跑在 rex 账户下，拿不到 ubuntu 的文件和权限，也不合适。
    # 退出登录后服务还在，靠的是 users.nix 里的 linger = true。
    services.rex.enable = true;

    # rex 的 ssh guard（从 rex 终端 ssh 出去时，别把 TERM=xterm-rex 带到不认识它的机器上）
    # 只能写进 HM 管理的 ~/.ssh/config。本机原来没有这个文件，所以接管不会冲掉什么。
    # 不要 HM 的默认 Host * 块：之前没有 config，用的就是 ssh 自己的默认值，这样行为不变。
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
    };
  };
}
