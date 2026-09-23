# ===== SillyTavern 原生服务 =====
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.services.sillytavern;
  stRoot = "${cfg.package}/lib/node_modules/sillytavern";

  # Claude Pro/Max 订阅登录的服务端插件（自己的仓库，见 flake input）。
  # 用 pnpm 锁文件把 node_modules 在 nix 里装好，整个插件目录进 store：
  # 上游 ST 的"clone 到 plugins/ 再 npm install"在只读的包目录里做不了，
  # 也不想让服务用户手工维护一份 node_modules。
  claudeOAuthPlugin = pkgs.stdenv.mkDerivation (finalAttrs: {
    pname = "sillytavern-claude-oauth";
    version = "0.1.0";
    src = inputs.sillytavern-claude-oauth;
    nativeBuildInputs = [
      pkgs.nodejs_24
      pkgs.pnpm_10
      pkgs.pnpmConfigHook
    ];
    # 插件的 .npmrc 已设 node-linker=hoisted，所以这里出来的是扁平 node_modules，
    # 和 npm 的布局一致，ST 的 plugin-loader 直接 import 即可。
    pnpmDeps = pkgs.fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      fetcherVersion = 4;
      # 插件 pnpm-lock.yaml 变了要重算：把 hash 置空 rebuild，抄报错里的 got:。
      hash = "sha256-fDCcM/jktDA+hs0ZstzkT7bu8gl8U/PiGfBIA775jYg=";
    };
    installPhase = ''
      mkdir -p $out
      cp -r index.mjs lib package.json node_modules $out/
    '';
  });
in
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

  # 服务端插件目录。ST 只从包内的 <pkg>/plugins 读（不可配），照上游模块处理
  # extensions 的办法把 /var/lib/SillyTavern/plugins 绑过去；目录里放 store 路径的
  # symlink（plugin-loader 用 statSync，跟随 symlink），要临时试别的插件也能直接丢进去。
  # sillytavern.yaml 里对应 enableServerPlugins: true、enableServerPluginsAutoUpdate: false
  # （自动更新会对每个插件目录跑 git pull，对 store symlink 没意义还会刷警告）。
  systemd.services.sillytavern.serviceConfig.BindPaths = [
    "%S/SillyTavern/plugins:${stRoot}/plugins"
  ];
  systemd.tmpfiles.settings.sillytavern = {
    "/var/lib/SillyTavern/plugins".d = {
      mode = "0700";
      inherit (cfg) user group;
    };
    "/var/lib/SillyTavern/plugins/claude-oauth"."L+" = {
      argument = "${claudeOAuthPlugin}";
      inherit (cfg) user group;
    };
  };
}
