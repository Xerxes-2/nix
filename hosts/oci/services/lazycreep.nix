# ===== lazycreep（自己的 Screeps 客户端）=====
{ inputs, ... }:
{
  imports = [ inputs.lazycreep.nixosModules.default ];

  # 无状态 Gateway（Caddy）：托管前端，把 Screeps 的 HTTP API / 房间历史 / 地图瓦片同源反代到官方。
  # 不存 token：token 只在浏览器里，X-Token 原样转发；写操作只放行 map-stats 与 console 两个 POST。
  # 仅监听本机，经 cloudflared 隧道暴露为 https://screeps.xerxes2.com
  # （Cloudflare dashboard 里的 public hostname → http://localhost:8080），
  # 前面套 Cloudflare Access 只放自己：不套的话谁都能拿它当 Screeps 的开放代理，
  # 官方看到的是本机 IP，滥用会连累自己被限流 / 封禁。
  services.lazycreep = {
    enable = true;
    port = 8080;
  };
}
