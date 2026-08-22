# ===== 用户 & sops 秘密 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  users.groups.ubuntu.gid = 1001;
  users.users.ubuntu = {
    isNormalUser = true;
    uid = 1001;
    group = "ubuntu";
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    linger = true; # 开机即拉起 user 服务（容器）
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUmTvXl/5tGe4e+alerNLGctJvGjeIWIrq3TeTitCUF2LLuWF49ea7j5XocB5TpBP1KcjXuzUuD0qBBrOdnKC0oX781MbiwdHSf0Cl6R5ZocyJl9Oxsu2Szjxq6Gkhw5u6dumbQHMV9fcPVSHDDuuSBjD3Cc0T1lPOUd3x2FJjebFEVDESXFJPZfKbzAgcBdxccl2T3lqEJ5RX8PeZ4RFK6yB+6G8jaqq8I4IoZU0P0toI568eRm3exGg8MtafY0kWk/FAuCRgmw+dQb2GjwPwP7cHprupbZNRkZaS/v5YJGudMXsa7nTGqQXyt5wAzPpTbvkkJbLhvhb35wN3eeFZ oracle"
    ];
    # 哈希由切换向导写入，lustrate 白名单保留 etc/secrets（mutableUsers 下仅首次建用户时生效）
    hashedPasswordFile = config.sops.secrets."ubuntu-hash".path;
  };
  # 串口控制台救援登录用，同上由向导写入
  users.users.root.hashedPasswordFile = config.sops.secrets."root-hash".path;

  # sops-nix：secrets 加密进 git（secrets/oci.yaml），主机 ssh ed25519 key 解密。
  # 密码哈希需 neededForUsers（用户创建早于常规 secrets 挂载）。
  # 旧 /etc/secrets/ 观察期后可删。
  sops = {
    defaultSopsFile = ../../secrets/oci.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      "ubuntu-hash".neededForUsers = true;
      "root-hash".neededForUsers = true;
      "cloudflared-env" = { };
      "wakapi-env" = { };
      "restic-env" = { };
      "restic-password" = { };
    };
  };

  # 与现状一致：ssh 仅密钥登录，sudo 免密（密码仅串口救援登录用）
  security.sudo.wheelNeedsPassword = false;

  programs.fish.enable = true;
  programs.nix-ld.enable = true; # 兼容家目录里非 nix 编译的二进制
}
