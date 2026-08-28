# OCI A1.Flex aarch64 — 由 Ubuntu 26.04 经 NIXOS_LUSTRATE 原地迁移。
# 本文件只是 NixOS 入口，实际配置拆到同目录的模块里（见 imports）。
{ ... }:
{
  imports = [
    ./boot.nix
    ./filesystems.nix
    ./network.nix
    ./users.nix
    ./packages.nix
    ./services/wakapi.nix
    ./services/sillytavern.nix
    ./services/restic.nix
    ./services/cloudflared.nix
    ./services/vaultwarden.nix
    ./services/ntfy.nix
    ./services/misc.nix
  ];
}
