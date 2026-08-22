# nixcfg — 多机 Nix 配置

一台 NixOS 服务器（`oci`）+ 一台装了 Nix 的 MacBook（`xerxes2`），全部由 `flake.nix` 声明式管理。
**不要再用 `nix profile install nixpkgs#xxx` 散装**，否则机器状态会漂移。

## 结构

```
├── flake.nix               # 入口：定义 oci / xerxes2 两台机器
├── hosts/oci/
│   ├── configuration.nix   # NixOS 入口，imports 下面的模块
│   ├── boot.nix filesystems.nix network.nix users.nix packages.nix
│   ├── services/           # wakapi / sillytavern / restic / cloudflared / misc
│   ├── home.nix            # ubuntu 用户的 Home Manager（含 dufs）
│   └── sillytavern.yaml    # SillyTavern 配置（无机密，进 git）
├── modules/
│   ├── home/cli.nix        # 跨机器共享的 CLI 工具集
│   └── unfree.nix          # unfree 包白名单
└── secrets/oci.yaml        # sops 加密的秘密
```

## 加一个包

先确定加在哪一层：

| 场景 | 文件 |
|---|---|
| 所有机器都要的 CLI 工具（bat、yazi…） | `modules/home/cli.nix` |
| 仅 oci 用户需要的工具（btdu…） | `hosts/oci/home.nix` |
| oci 系统级工具（htop、rsync…） | `hosts/oci/packages.nix` 的 `environment.systemPackages` |

找包名：https://search.nixos.org 或 `nix search nixpkgs xxx`。

## 应用变更

oci（NixOS，系统 + Home Manager 一起）：
```bash
cd ~/nixcfg
nixos-rebuild switch --flake .#oci
# 本机上已设主机名别名，`--flake ~/nixcfg` 或 `--flake .` 亦可
```

xerxes2（Mac，standalone home-manager）：
```bash
nix run home-manager -- switch --flake ~/nixcfg#xerxes2
```

> 用 `sudo nixos-rebuild` 时 `~` 会展开成 `/root`，务必写绝对路径
> `/home/ubuntu/nixcfg#oci`。

## 升级全部包

```bash
cd ~/nixcfg
nix flake update          # 更新锁文件（nixpkgs 到最新 weekly）
nixos-rebuild switch --flake .#oci
```

## 回滚

```bash
nixos-rebuild switch --rollback    # 回到上一代系统配置
# 或 jj/git 层面回退 flake.lock 后重建
```

## 换新机器还原

```bash
git clone <本仓库> ~/nixcfg      # jj 仓库兼容 git clone
cd ~/nixcfg
nixos-rebuild switch --flake .#oci
```

## 清理磁盘

```bash
nix store gc
```

## 迁移历史

从 Ubuntu 26.04 经 NIXOS_LUSTRATE 原地迁移、三个 rootless 容器迁为原生服务的记录，
都在提交历史里：`jj log`。
