# Mac mini Mid 2011 Server（Macmini5,3）：家里的无头折腾机，全程 ssh 远程。
# 2026-10 从 U 盘（BIOS 兼容模式启动的 NixOS minimal ISO）nixos-install 装上。
{ pkgs, ... }:
{
  imports = [ ./hardware.nix ];

  networking.hostName = "macmini";
  # Wi‑Fi 密码不进仓库：安装时把 U 盘系统里 nmtui 连好的
  # /etc/NetworkManager/system-connections/*.nmconnection 拷进了目标盘。
  # 换网络就 ssh 上去 nmcli / nmtui。
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # 局域网里直接 `ssh macmini.local`，不用去路由器查 IP。
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  time.timeZone = "Australia/Melbourne";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.xerxes2 = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    # 每机一把，和 hosts/oci/users.nix 同一批公钥。
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMJYY+oB7f+EX9rSf/KhnBmL0v9fOqMYDIwolS14ap+ xerxes2@asahi->oci 2026-08"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIOTESA/rYKuqMWmrKy5iUHn8gOMpi3g4TPOAAzf8Trc xerxes2@cachyos->oci 2026-08"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKe93U8tukqAUuWdVF+c7Swzv0zE6ar5U+nGKNZxOiH xerxes2@darwin->oci 2026-08"
    ];
  };
  # 没接 sops、也没设登录密码：账户只能用 ssh key 进。sudo 免密是这台
  # 折腾机的取舍——不像 oci 那样对公网提供服务，不值得为第二道关维护一份密码哈希。
  security.sudo.wheelNeedsPassword = false;
  programs.fish.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  environment.systemPackages = with pkgs; [
    bcachefs-tools
    smartmontools
    pciutils
    usbutils
    iw
    ethtool
    kitty.terminfo # ssh 会话按 /etc/terminfo 查找，须留系统级
  ];

  # 无头：不要 NixOS 手册
  documentation.nixos.enable = false;

  # 首次安装即为该版本，之后勿改
  system.stateVersion = "26.11";
}
