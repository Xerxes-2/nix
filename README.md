# nixcfg — 声明式包管理小抄

所有 CLI 工具由 `flake.nix` 统一声明。**不要再用 `nix profile install nixpkgs#xxx` 散装**，否则文件和机器状态会漂移。

## 加一个包

1. 编辑 `flake.nix`，在 `paths = with pkgs; [ ... ]` 里加上包名
   （找包名：https://search.nixos.org 或 `nix search nixpkgs xxx`）
2. 应用变更：

```bash
cd ~/nixcfg
nix profile upgrade nixcfg
git commit -am "add xxx"
```

## 删一个包

同上：从 `flake.nix` 删掉那行，然后 `nix profile upgrade nixcfg`。

## 升级全部包

```bash
cd ~/nixcfg
nix flake update          # 更新锁文件（nixpkgs 到最新 weekly）
nix profile upgrade nixcfg
git commit -am "update $(date +%F)"
```

⚠️ herdr 钉在 commit `2bc1724`（避免每次在本机重新编译 Rust）。
想升级它时：把 `flake.nix` 里 herdr.url 的 commit 换成新的（或临时去掉
`/2bc1724...` 后缀跑 `nix flake update herdr`），会触发一次本地编译，耐心等。

## 回滚

```bash
nix profile rollback                 # 回到上一代 profile
# 或 git 层面：
git -C ~/nixcfg checkout HEAD~1 -- flake.lock && nix profile upgrade nixcfg
```

## 换新机器还原环境

```bash
git clone <本仓库> ~/nixcfg
nix profile add ~/nixcfg
```

## 清理磁盘

```bash
nix store gc
```
