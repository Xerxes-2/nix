# btrfs 排查工具（NixOS 模块，两台 Linux 机器共用）。
#
# 走 environment.systemPackages 而不是 home.packages：两个工具都得以 root 跑
# （btrfs 的 SEARCH_V2 ioctl 要 CAP_SYS_ADMIN），装进用户 profile 的话
# /etc/profiles/per-user/<user>/bin 不在 root 的 PATH 里，`sudo -i` 或 `su -`
# 之后就找不到命令。`sudo xsz` today 能用只是因为这台机器没配 secure_path
# ——不值得依赖。
#
# 同理没并进 modules/home/cli.nix：那个模块 darwin 侧也导入，而这两个工具都是
# btrfs 专用，xsz 的 flake 更是只出 aarch64-linux / x86_64-linux。
#
# 两个工具回答的不是同一个问题：
#   btdu  采样式统计「谁占了空间」，交互式钻目录树，适合找占地大户。
#         要求路径挂在 subvolid=5（顶层子卷）上，否则直接拒绝运行。
#   xsz   精确核算一组文件的实际占用，把压缩、reflink、被部分覆盖的 extent
#         都算进去——也就是 du 和 df 都答不对的那部分。在子卷根上加 -t
#         直接扫 tree，比走目录层级快很多。
#
# xsz 的用处在 2026-08 那次子卷重排里很具体：拷贝是 reflink 的，删掉 @ 里的老
# 副本后 df 几乎没变，因为 extent 还被 @nix / @varlib 引用着。du 看不出共享，
# df 只给全盘数字，xsz 能直接说清某棵子树独占多少、共享多少。
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    # 不在 nixpkgs 里，来自第三方 flake（见 flake.nix 的 inputs.xsz）。
    # 提供 xsz 和 xfrag 两个 binary。
    inputs.xsz.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.btdu
  ];
}
