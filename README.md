# nixcfg — 多机 Nix 配置

三个部署目标，全部由 `flake.nix` 声明式管理：

| 目标 | 是什么 | 怎么管 |
|---|---|---|
| `oci` | Oracle Cloud 的 aarch64 服务器 | NixOS + Home Manager |
| `asahi` | 14" MacBook Pro (M2 Pro) 上的 Asahi Linux | NixOS + Home Manager |
| `XueMacBook-Pro` | **同一台 MacBook 的 macOS 侧** | nix-darwin + Home Manager |

`asahi` 和 `XueMacBook-Pro` 是同一台物理机器的两个系统——Asahi Linux 必须与 macOS 双启动，
所以 macOS 那边也用 nix-darwin（Determinate Nix）管起来：系统级 GUI 应用、字体、
homebrew（tap/formula/cask 全部声明式）、macOS defaults，外加作为模块运行的
Home Manager，共用 `modules/home/cli.nix` 那套 CLI 工具。

**不要再用 `nix profile install nixpkgs#xxx` 散装**，否则机器状态会漂移。

## 仓库位置与版本控制

两台 NixOS 机器上都在 **`/etc/nixos`**，macOS 侧在 **`~/.config/nix`**，
都用 **jj**（colocated，git 作为后端）。

`git log` / `git branch` 能看，但**不要用 git 改**：colocated 仓库的 git HEAD 永远是
detached 的，那是 jj 的正常状态而非故障，用 `git checkout` / `git reset` 去"修"会和
jj 的工作副本打架。

## 结构

```
├── flake.nix               # 入口：定义 oci / asahi / XueMacBook-Pro
├── hosts/oci/
│   ├── configuration.nix   # NixOS 入口，imports 下面的模块
│   ├── boot.nix filesystems.nix network.nix users.nix packages.nix
│   ├── services/           # wakapi / sillytavern / vaultwarden / restic / cloudflared / misc
│   ├── home.nix            # ubuntu 用户的 Home Manager（含 dufs）
│   └── sillytavern.yaml    # SillyTavern 配置（无机密，进 git）
├── hosts/asahi/
│   ├── configuration.nix   # NixOS 入口，imports 下面的模块
│   ├── hardware-configuration.nix   # 生成的，别手改
│   ├── filesystems.nix     # btrfs 压缩/挂载选项，叠加在上面那份之上
│   ├── power.nix           # zswap / 电池上限 / 电源键 / systemd-oomd
│   ├── dualboot.nix        # 切回 macOS、同步 macOS 的蓝牙/Wi-Fi 凭据
│   ├── gui.nix             # niri + DMS + 音频 + 字体 + Widevine
│   ├── display.nix         # 内屏刘海几何的唯一真相，缩放改这里
│   ├── input.nix           # fcitx5 双拼
│   ├── containers.nix      # podman / distrobox
│   ├── niri/               # config.kdl + 软件夜间模式补丁（见 gui.nix 的注释）
│   ├── dms/settings.nix    # DMS 首次启动的初始布局
│   ├── home.nix            # xerxes2 用户的 Home Manager
│   └── steam/              # Fedora Asahi 游戏栈容器（FEX + muvm），见其 README
├── hosts/darwin/
│   ├── configuration.nix   # nix-darwin 入口：GUI 应用、字体、homebrew、defaults
│   └── home.nix            # xerxes2 用户的 Home Manager（fish/starship/git/gpg…）
├── modules/
│   ├── home/cli.nix        # 跨机器共享的 CLI 工具集
│   └── unfree.nix          # unfree 包白名单
└── secrets/oci.yaml        # sops 加密的秘密
```

## 加一个包

先确定加在哪一层：

| 场景 | 文件 |
|---|---|
| 所有机器都要的 CLI 工具（git、htop、bat、yazi…） | `modules/home/cli.nix` |
| 仅 oci 用户需要的工具（btdu…） | `hosts/oci/home.nix` |
| oci 服务器/btrfs 专用或须系统级的包 | `hosts/oci/packages.nix` |
| asahi 的 GUI 程序、字体 | `hosts/asahi/gui.nix` |
| asahi 的输入法相关 | `hosts/asahi/input.nix` |
| asahi 上与 macOS 双启动相关的工具 | `hosts/asahi/dualboot.nix` |
| macOS 的 GUI 应用、字体（nixpkgs 有的） | `hosts/darwin/configuration.nix` |
| macOS 特有的 CLI 工具 | `hosts/darwin/home.nix` |
| nixpkgs 没有/只能用 brew 的（cask、专有字体） | `hosts/darwin/configuration.nix` 的 homebrew 块 |

找包名：https://search.nixos.org 或 `nix search nixpkgs xxx`。

## 应用变更

两台 NixOS 机器的主机名都能对上 flake 里的 attribute（`asahi` 直接同名；oci 的真实
主机名 `instance-20260821-1942` 在 `flake.nix` 里做了别名），所以 `#target` 可以省略：

```bash
sudo nixos-rebuild switch --flake /etc/nixos          # 本机
```

macOS 侧（nix-darwin，主机名 XueMacBook-Pro 能对上 attribute，`#…` 可省）：
```bash
sudo darwin-rebuild switch --flake ~/.config/nix
```

> 在 NixOS 上用 `sudo` 时 `~` 会展开成 `/root`，写绝对路径 `/etc/nixos`；
> macOS 的 sudo 保留用户的 `$HOME`，`~/.config/nix` 没问题。

## 在另一台机器上同步

改动推上去之后，到另一台机器：

```bash
cd /etc/nixos
jj git fetch
jj new main                                    # 或 jj edit main
sudo nixos-rebuild switch --flake /etc/nixos
```

**不要用 `git pull`**。它在 colocated 仓库里能跑，但绕过了 jj——jj 只能在下一条命令时
被动 import 并重置工作副本，属于让它替你兜底。

想先确认这次 switch 会动什么：

```bash
nix build --no-link --print-out-paths .#nixosConfigurations.oci.config.system.build.toplevel
nix store diff-closures /run/current-system <上面那个路径>
```

## 升级全部包

```bash
cd /etc/nixos
nix run .#update                      # 更新全部输入，并自动提交
nix run .#update -- nixpkgs-unstable  # 只更新指定输入
nix run .#update -- --dry-run         # 只看会生成什么提交信息
sudo nixos-rebuild switch --flake /etc/nixos
```

不要直接用 `nix flake update`：它一次动好几个输入，落成一个没有描述的
flake.lock 改动，事后看不出带进来什么。上面那个包装会把每个输入的 rev、
日期变化和 GitHub compare 链接写进提交信息。（已经手动改过 lock 的话，
`nix run .#update -- --commit-only` 可以补一个描述。）

更新后先求值再切，能提前抳掉选项重命名类的破坏：

```bash
nix eval --raw .#nixosConfigurations.asahi.config.system.build.toplevel.drvPath
```

asahi 的内核来自 `nixos-apple-silicon`，上游**没有 binary cache**（见其
`docs/binary-cache.md`），所以 nixpkgs 一动就要本地编内核，几十分钟起步。

## 更新 Asahi 固件

`asahi-firmware` 是一个 `path:/boot/vendorfw` 输入，内容被 flake.lock 按哈希锁住。
在 macOS 侧跑过 Asahi 安装器的 "Rebuild vendor firmware package" 之后，必须重新锁定
才会生效（**只能在 MacBook 上做**，那个路径只有它有）：

```bash
nix flake update asahi-firmware
sudo nixos-rebuild switch --flake /etc/nixos
```

正因为它是本机路径，在 oci 上裸跑 `nix flake update` 会直接中止、一个输入都更不了：

```
error: path '//boot/vendorfw' does not exist
```

`nix run .#update` 会自动跳过本机不存在的本地 path 输入，所以两台机器上都能直接跑。

## 切回 macOS

启动盘的选择存在 NOR flash 的 NVRAM 里，`asahi-bless` 负责改它。包了一层：

```bash
boot-macos          # 只把「下次启动」设成 macOS，然后自己重启；终端里跑会问一句
boot-macos --now    # 设好之后立刻重启
```

**默认启动盘始终是 NixOS**（用的是 `--next`），所以从 macOS 重启回来自动就是 Linux，
不需要事后再 bless 一次。启动器里的 `Boot macOS Next` 是同一个脚本——它只打标记、不会
立刻重启，免得模糊搜索一回车就把没保存的东西弄丢。

想看/改默认启动盘用 `sudo asahi-bless -l`。

## 同步 macOS 的蓝牙配对和 Wi-Fi 密码

macOS 把蓝牙配对密钥和 Wi-Fi 密码也写在同一块 NVRAM 里，可以搬到 Linux 这边，省掉
每次切系统重新配对耳机、重输密码：

```bash
sudo asahi-btsync list && sudo asahi-btsync sync      # 蓝牙配对密钥 -> bluez
sudo asahi-wifisync list && sudo asahi-wifisync sync  # Wi-Fi 密码 -> NetworkManager
```

刻意没做成开机自动跑：配对不常变，而 `sync` 会改 `/var/lib/bluetooth` 并让 bluetoothd
重载配置。在 macOS 侧配好新设备之后手动跑一次就够了。

## 回滚

```bash
sudo nixos-rebuild switch --rollback    # 回到上一代系统配置
# 或在 jj 层面回退 flake.lock 后重建
```

注意 asahi 上 `boot.loader.systemd-boot.configurationLimit = 5`：ESP 只有 504M，
能回滚的代数就这么多，更早的已经从启动菜单里清掉了。

## 换新机器还原

```bash
sudo jj git clone --colocate https://github.com/Xerxes-2/nix.git /etc/nixos
sudo nixos-rebuild switch --flake /etc/nixos#<target>
```

（没有 jj 也可以直接 `git clone`，仓库对纯 git 是兼容的。）

asahi 还需要 `/boot/vendorfw/firmware.cpio` 存在（由 Asahi 安装器写入），
以及一份本机生成的 `hosts/asahi/hardware-configuration.nix`。

macOS 侧（先装 Determinate Nix 和 homebrew）：

```bash
jj git clone --colocate https://github.com/Xerxes-2/nix.git ~/.config/nix
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/.config/nix
```

第一次 switch 之后 `darwin-rebuild` 就在 PATH 里了。

## 清理磁盘

```bash
nix store gc
```

两台 NixOS 机器都已开 `nix.gc.automatic` 和 `nix.optimise.automatic`（都是每周，
asahi 保留 30 天、oci 保留 14 天），正常不需要手动跑。

## 已知的坑

**DRM 流媒体（Netflix / Spotify Web / Prime）需要 Widevine，Mozilla 不给 aarch64 出。**
`gui.nix` 里按 Asahi 上游的办法自己装了一份（从 ChromeOS 镜像里取 arm64 CDM 再改 ELF），
Zen 和 Firefox 都配好了。它是 unfree 且不可再分发的，所以在 `modules/unfree.nix` 里单独放行。
播不出来时先看 `about:support` 里 `media.gmp-widevinecdm` 有没有加载。

**USB-C 外接显示器（DP alt mode）在稳定内核上没有**，要自己编 `fairydust` 分支。HDMI
可用。

**合盖休眠每小时掉 2-3% 电**，是 s2idle 的已知状态（AsahiLinux/linux#262），配置层面
无解。

**新文件必须先让 jj 快照到。** flake 求值读的是 git 的跟踪状态，刚创建、还没被任何
jj 指令快照过的新文件对 nix 不可见：

```
error: Path 'hosts/asahi/power.nix' in the repository "/etc/nixos" is not tracked by Git.
```

跑任意一条 jj 指令（`jj st` 就行）即可：自动快照会把新文件以 intent-to-add 登记进
git 索引，nix 便认作已跟踪并读到工作树的完整内容，不需要先 `jj commit`。
（`git add <文件>` 也能解决。）

## 复查清单（TODO）

所有绕开上游 bug 的补丁、以及跟着上游版本会失效的假设，都在原地留了统一格式的
`TODO revisit:` 注释——写清楚**什么时候回来看、怎么验证、验证过了怎么改**，以及上次
检查的时间和结论。列出来：

```bash
rg -n --glob '!flake.lock' 'TODO revisit' /etc/nixos
```

升级 `nixpkgs` / 内核 / dms-shell 之后按这份清单走一遍，能删的就删掉，删不掉的把
`last:` 那行的日期和结论更新掉。

## 迁移历史

从 Ubuntu 26.04 经 NIXOS_LUSTRATE 原地迁移、三个 rootless 容器迁为原生服务的记录，
都在提交历史里：`jj log`。
