# ===== Nix 设置与系统级包 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
  };
  # 定时硬链接去重，替代 auto-optimise-store（后者拖慢每次构建）
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # 只留服务器专用与必须系统级的包；
  # 通用 CLI 工具在 modules/home/cli.nix（跨机器共享），
  # 两台 NixOS 共用的 btrfs 工具（btdu、xsz）在 modules/btrfs-tools.nix。
  environment.systemPackages = with pkgs; [
    bottom # btm
    btrfs-progs
    bubblewrap
    chromium
    duperemove
    fio
    kitty.terminfo # SSH 会话按 /etc/terminfo 查找，须留系统级
    restic
  ];

  # 无头服务器：裁掉 NixOS 手册等文档，减小闭包、加快 rebuild
  documentation.nixos.enable = false;

  # 首次安装即为该版本，之后勿改
  system.stateVersion = "26.05";
}
