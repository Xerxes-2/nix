# ===== battlesnake（自己的 Battlesnake 蛇，F#）=====
{ inputs, ... }:
{
  imports = [ inputs.battlesnake.nixosModules.default ];

  # 无状态 HTTP 服务：Battlesnake 引擎每回合 POST /move，回一个方向。
  # 仅监听本机，经 cloudflared 隧道暴露为 https://snake.xerxes2.com
  # （Cloudflare dashboard 里的 public hostname → http://localhost:8100）。
  # 与 lazycreep / ST 不同，前面**不能**套 Cloudflare Access：调用方是 Battlesnake 的
  # 游戏服务器，过不了登录页。暴露出去也只是个算走法的接口，没有状态、不代理任何东西。
  # 走隧道而不是直接开端口：TLS 在离引擎（GCP Oregon）最近的 Cloudflare 节点终结，
  # 跨太平洋的只剩已建好的隧道连接，省掉每回合握手的往返（500ms 超时里网络约占 175ms）。
  services.battlesnake = {
    enable = true;
    # 8000 被 SillyTavern 占了
    port = 8100;
  };
}
