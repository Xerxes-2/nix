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
  # 插件零运行时依赖：Claude OAuth 流程由上游的 scripts/build-vendor.mjs 预先打进
  # vendor/，package.json 的 dependencies 是空的（上游 README："没有第二步，也不用
  # npm install"）。所以这里不跑 pnpm，源码原样进 store 就是一个完整的插件——
  # 反正上游 ST 那套"clone 到 plugins/ 再 npm install"在只读的包目录里也做不了。
  # 下面的断言盯着 dependencies：哪天上游真加了运行时依赖，构建会停在这里，
  # 而不是悄悄装出一个 import 就炸的插件（那时再把 pnpm 打包方式加回来）。
  claudeOAuthPlugin = pkgs.stdenv.mkDerivation {
    pname = "sillytavern-claude-oauth";
    version = "0.1.0";
    src = inputs.sillytavern-claude-oauth;
    nativeBuildInputs = [ pkgs.jq ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      deps=$(jq -r '.dependencies // {} | length' package.json)
      if [ "$deps" != "0" ]; then
        echo "插件 package.json 现在有 $deps 个运行时依赖，这份表达式只拷源码，" >&2
        echo "装出来的插件会缺 node_modules：需要改回 pnpm 打包（pnpm.fetchDeps + pnpm.configHook）。" >&2
        exit 1
      fi
      mkdir -p $out
      # vendor/ 是运行时必需的（lib/pi-oauth.mjs 从这里加载 OAuth 流程和它的 manifest）。
      cp -r index.mjs lib vendor package.json $out/
      runHook postInstall
    '';
  };
in
{
  # SillyTavern 原生服务（从 rootless 容器迁入，2026-08）。
  # 模块以 XDG_DATA_HOME=/var/lib 运行全局模式，数据在 /var/lib/SillyTavern/data，
  # 第三方扩展在 /var/lib/SillyTavern/extensions（BindPaths 映射进包目录）。
  # config 无机密（basicAuth/proxy 均为未启用的出厂默认），直接进 git；
  # 监听 127.0.0.1:8000（listen: false），cloudflared 走 localhost，隧道域名前面套
  # Cloudflare Access 只放自己（dashboard 里的 public hostname → http://localhost:8000）。
  # 不用 ST 自带的两层认证：whitelist 在同机代理下没有意义（对端全是 127.0.0.1，
  # 而开启 forwarded whitelist 又要求把动态出口 IP 列进去），basicAuth 则会把密码
  # 明文写进这份进 git 的 yaml，而且它只在 listen: true 时才装载（server-main.js）。
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
  systemd.services.sillytavern = {
    serviceConfig.BindPaths = [
      "%S/SillyTavern/plugins:${stRoot}/plugins"
    ];
    # 新文件对组可读写（配合下面的 2770 目录和 ubuntu 入组），其他人不可见。
    serviceConfig.UMask = "0007";
    # 插件换版本只是 tmpfiles 改了一个 symlink，unit 本身没变，switch 不会重启服务，
    # 旧代码会一直留在内存里。把插件包列为触发器让它跟着重启。
    restartTriggers = [ claudeOAuthPlugin ];
  };
  # ubuntu 入 sillytavern 组，免 sudo 直接读写数据；服务仍以 sillytavern 身份在沙箱里跑。
  # 目录 2770：组可读写，setgid 让新文件继承 sillytavern 组。tmpfiles 的 d 只管目录本身，
  # 已有内容需一次性手动修：chmod -R g+rwX,o-rwx + 给子目录 g+s。
  # 注意 ubuntu 默认 umask 022，手动放进去的文件要 chmod g+w，服务才能改。
  users.users.ubuntu.extraGroups = [ cfg.group ];
  systemd.tmpfiles.settings.sillytavern = {
    "/var/lib/SillyTavern/data".d.mode = lib.mkForce "2770";
    "/var/lib/SillyTavern/extensions".d.mode = lib.mkForce "2770";
    "/var/lib/SillyTavern/plugins".d = {
      mode = "2770";
      inherit (cfg) user group;
    };
    "/var/lib/SillyTavern/plugins/claude-oauth"."L+" = {
      argument = "${claudeOAuthPlugin}";
      inherit (cfg) user group;
    };
  };
}
