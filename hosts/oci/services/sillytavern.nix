# ===== SillyTavern 原生服务 =====
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # SillyTavern 原生服务（从 rootless 容器迁入，2026-08）。
  # 模块以 XDG_DATA_HOME=/var/lib 运行全局模式，数据在 /var/lib/SillyTavern/data，
  # 第三方扩展在 /var/lib/SillyTavern/extensions（BindPaths 映射进包目录）。
  # config 无机密（basicAuth/proxy 均为未启用的出厂默认），直接进 git；
  # 监听 127.0.0.1:8000（listen: false）+ whitelist，cloudflared 走 localhost。
  services.sillytavern = {
    enable = true;
    # 注意：必须插值成 string，模块把它直接传给 tmpfiles 的 L+ argument（要求 string）
    configFile = "${../sillytavern.yaml}";
  };
}
