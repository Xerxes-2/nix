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

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    htop
    btrfs-progs
    # 从 Ubuntu apt 手动安装集迁移而来
    bottom # btm
    btop
    bubblewrap
    chromium
    compsize
    duperemove
    eza
    fastfetch
    fio
    gh
    kitty.terminfo
    lnav
    nano
    restic
    ripgrep
    rsync
    sqlite
    tokei
    tree
    unar
    unzip
    wget
    zip
  ];

  # 无头服务器：裁掉 NixOS 手册等文档，减小闭包、加快 rebuild
  documentation.nixos.enable = false;

  # 首次安装即为该版本，之后勿改
  system.stateVersion = "26.05";
}
