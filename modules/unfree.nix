# unfree 包白名单——所有机器共用。
# NixOS 与 standalone home-manager 的模块系统都有 nixpkgs.config 选项，
# 故此文件可同时作为两者的模块导入。
# 注意：oci 上 home-manager.useGlobalPkgs = true，HM 层不可再设 nixpkgs.config，
# 因此 oci 只在 NixOS 层（flake.nix 的 modules 列表）导入本文件。
{ lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
      # Widevine CDM，asahi 的浏览器放 DRM 流媒体要用；见 hosts/asahi/gui.nix。
      "widevine-cdm"
      # 以下为 darwin 侧 GUI 应用：
      # BUSL 许可证的 ZeroTier 客户端；压缩工具 Keka。
      "zerotierone"
      "keka"
    ];
}
