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
都用 **jj**（colocated，git 作为后端）。所有改动走 jj、git 只读——
具体约定（为什么 git HEAD 是 detached、提交信息格式、新文件快照）见 `AGENTS.md`。

## 结构

```
├── flake.nix               # 入口：定义 oci / asahi / XueMacBook-Pro
├── hosts/oci/
│   ├── configuration.nix   # NixOS 入口，imports 下面的模块
│   ├── boot.nix filesystems.nix network.nix users.nix packages.nix
│   ├── services/           # wakapi / sillytavern / vaultwarden / ntfy / restic / cloudflared / chive / oracle-cloud-agent / misc
│   ├── home.nix            # ubuntu 用户的 Home Manager（含 dufs）
│   ├── sillytavern.yaml    # SillyTavern 配置（无机密，进 git）
│   └── chive.toml          # chive 虚拟仓配置（无机密，进 git）
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
│   ├── btrfs-tools.nix     # btdu + xsz，两台 NixOS 共用（系统级，Linux only）
│   └── unfree.nix          # unfree 包白名单
├── scripts/
│   └── flake-update.sh     # 更新 flake.lock 并把改了什么写进提交信息
└── secrets/oci.yaml        # sops 加密的秘密
```

## btrfs 子卷布局

**oci**（`/dev/sda1`，全部 `noatime,compress-force=zstd:3,discard=async`）：

| 子卷 | 挂载点 | 快照 | 备注 |
|---|---|---|---|
| `@` | `/` | — | 可从 flake 重建，不值得快照 |
| `@nix` | `/nix` | — | store，全盘最大且完全可复现 |
| `@varlib` | `/var/lib` | snapper `varlib` | vaultwarden / wakapi / SillyTavern / ntfy 的状态，以及 chive 的账本 |
| `@home` | `/home` | snapper `home` | dufs-data |
| `@log` | `/var/log` | — | journald 限 500M |
| `@cache` | `/var/cache` | — | chive 的 aggTrades 缓存（数 GB，可重下，故不快照不备份） |
| `@tmp` | `/var/tmp` | — | `/tmp` 是 tmpfs，不在盘上 |

快照保留：每小时一张，留 6 小时 + 7 天。克制是因为 bees 去重开销随快照数增长，
且快照会钉住已删数据。异地备份是另一层（restic → OCI Object Storage）。

**asahi**：`@` / `@home` / `@nix`，`compress-force=zstd:1`（等级选型的实测数据写在
`hosts/asahi/filesystems.nix` 的注释里）。无快照。

### 看空间到底被谁占了

`df` 和 `du` 在这上面都会骗人：`du` 不知道 extent 被多个子卷共享，`df` 只给全盘
数字，两者都不看压缩。两个工具装在 `modules/btrfs-tools.nix`：

- `btdu` —— 采样式统计「谁占了空间」，交互式钻目录树，找占地大户
- `xsz` —— 精确核算一组文件的实际占用，把压缩、reflink、被部分覆盖的 extent 都算进去；
  在子卷根上加 `-t` 直接扫 tree，比走目录层级快很多

具体例子：上面那次子卷重排后删掉 `@` 里的老 `/nix`，`df` 几乎没变——因为拷贝是
reflink 的，extent 还被 `@nix` 引用着。这种「删了但没释放」只有 `xsz` 能说清。

两个都得以 root 跑（btrfs 的 SEARCH_V2 ioctl 要 CAP_SYS_ADMIN），所以走
`environment.systemPackages` 而不是 `home.packages`——后者落在
`/etc/profiles/per-user/<user>/bin`，那不在 root 的 PATH 里，`sudo -i` 或 `su -`
之后就找不到命令。`sudo xsz` 能用只是因为这两台没配 `secure_path`。

`xsz` 不在 nixpkgs 里，从第三方 flake 进来（`inputs.xsz`），只出 Linux，所以也没放进
darwin 也在用的 `modules/home/cli.nix`。

`btdu` 还要求路径挂在 `subvolid=5`（顶层子卷）上，直接对 `/` 跑会被拒。

### 再改布局的话

改布局要搬数据，不是改个 `.nix` 就完事。oci 那次（`@` → 拆出 `@nix` + `@varlib`）
的脚本已经删了——它硬编码了 UUID，且 phase 4 的 `rsync --delete` 在迁移完成后源目录
已空，再跑一次会把 `@varlib` 里的服务状态全抹掉。要找它：提交 `zroqpkvk` 的父提交。

重写时要保留的四个要点：

1. **先 `nixos-rebuild boot`，再拷贝。** rebuild 会往还活着的老 `/nix` 写新 store 路径，
   拷贝必须发生在它之后，新一代才拿得到自己需要的东西。
2. **`cp -a --reflink=always`，源路径取子卷原位置**（`subvolid=5` 挂下的 `@/nix`），
   不走 `/nix/store` 那层 ro bind mount。`-a` 含 `--preserve=links`，
   `nix-store --optimise` 的硬链接保得住；reflink 让副本共享 extent。
3. **老数据先留着，分开一阶清理。** 新一代启不起来就在 GRUB 里选上一代——它的 stage-1
   不挂新子卷，会照常用 `@` 里的老副本。清理之后这条路就没了。
4. **清理时只能清空目录，不能删目录**（见下面那条坑）。

## 加一个包

先确定加在哪一层：

| 场景 | 文件 |
|---|---|
| 所有机器都要的 CLI 工具（git、htop、bat、yazi…） | `modules/home/cli.nix` |
| 两台 NixOS 都要的 btrfs 工具（btdu、xsz） | `modules/btrfs-tools.nix` |
| 仅 oci 用户需要的工具 | `hosts/oci/home.nix` |
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

## 服务出问题时会推送到手机（ntfy）

`hosts/oci/services/ntfy.nix`：oci 上跑 ntfy 服务端，15 个关键单元挂了 `OnFailure=`，
失败时把 `systemctl status` 的尾巴推到 topic **`oci-alerts`**。

订阅（手机装 ntfy app，或浏览器开 https://ntfy.xerxes2.com）：

| 项 | 值 |
|---|---|
| 服务器 | `https://ntfy.xerxes2.com` |
| topic | `oci-alerts` |
| 账号 | `admin`，密码在 vaultwarden 里 |

服务器默认 `auth-default-access: deny-all`（公网可达，不能当公共中转），用户 / ACL /
令牌全部走 sops `ntfy-env` 声明式下发，**不要用 `ntfy user add` 改**——声明式条目每次
启动都会覆盖回来。发告警的是单独的 `alerts` 账号，对 `oci-alerts` 只有 write-only。

改覆盖范围：编辑 `ntfy.nix` 里的 `monitoredUnits` 列表。新加服务时记得回来加一行。

自测一条（`%n` 只在解析 unit 文件时展开，`systemd-run --property=` 走 D-Bus
不做 specifier 展开，所以这里必须把实例名写全）：

```bash
sudo systemd-run --unit=ntfy-selftest \
  --property=OnFailure=notify-failure@ntfy-selftest.service.service \
  /run/current-system/sw/bin/false
```

只想验证推送链路（令牌、网络）而不管 OnFailure 接线，可以直接跑通知器：

```bash
sudo systemctl start 'notify-failure@sshd.service.service'
```

**两个覆盖不到的盲区**：ntfy 自己挂了、整台机器失联——这两种情况没人能发出告警。
要补需要外部的 dead-man's switch（healthchecks.io 之类，或另一台机器上的 gatus）。

## 虚拟仓（chive paper）

`hosts/oci/services/chive.nix` + `hosts/oci/chive.toml`。跟着币安公开成交流跑一个模拟账本：
不下单、不签名、不读私钥，所以 sops 里没有它的东西。策略是 `breakout`（BTC/ETH 各 500）。

| 东西 | 位置 | 为何 |
|---|---|---|
| 账本（唯一真状态） | `/var/lib/chive/archive/*.toml` | 几 KB，每 60 秒原子重写；白拿 snapper 快照 + restic 异地 |
| aggTrades 缓存 | `/var/cache/chive`（经 `…/chive/aggtrades` symlink） | 数 GB 公开档案，可重下；不快照不备份，180 天按龄清理 |
| 配置 | git 里那份，每次启动覆盖到 `/var/lib/chive/chive.toml` | 直接改机器上那份会被覆盖 |

**首次启动要热身**：拉 56 天 aggTrades 建 Channel（6-8 GB CSV，压缩后少很多），
这段时间结构上不可能成交（种子期），几分钟后进 live。

**一两个月没任何成交是正常的**：这条规则六年回测里平均每 symbol 每年只开 3.5 笔、
在场率 34%。判断它活着看的是面板的 `Marked at` 时间而不是成交数：

```bash
journalctl -fu chive-paper                 # 日志（非 TTY 下面板降级为纯日志）
cat /var/lib/chive/archive/BTCUSDT.toml    # 账本本身就是给人读的：saved_at / 持仓 / Risk Line
```

**拒绝启动会叫醒你**：档案被改过、截断、版本与配置不符、两个 tenant 的段同时在场，
chive 会拒绝启动而不是静默重建一个空策略。`Restart=always` 配 5 次/小时的上限，
超过就进 failed → ntfy。升级（`nixos-rebuild switch`）无需手工步骤：
旧进程被杀与干净停止同义，新进程恢复账本、catch-up 自动补缺口。

**对账**（虚拟仓跑了一段时间之后）：同一个二进制已在 PATH 里。自己弄个工作目录：
Backtest 要往当前目录写 CSV，而 `/var/lib/chive` 是 chive 用户的。

```bash
mkdir -p ~/chive-check && cd ~/chive-check
ln -sfn /var/cache/chive aggtrades              # 复用服务已经下好的行情
cp /var/lib/chive/rules-snapshot.toml .         # Backtest 拒绝在没有它的情况下跑
chive backtest --strategy breakout \
  --symbol BTC/USDT --from <虚拟仓首日> --to <今天> --principal 500
```

## 已知的坑

**DRM 流媒体（Netflix / Spotify Web / Prime）需要 Widevine，Mozilla 不给 aarch64 出。**
`gui.nix` 里按 Asahi 上游的办法自己装了一份（从 ChromeOS 镜像里取 arm64 CDM 再改 ELF），
Zen 和 Firefox 都配好了。它是 unfree 且不可再分发的，所以在 `modules/unfree.nix` 里单独放行。
播不出来时先看 `about:support` 里 `media.gmp-widevinecdm` 有没有加载。

**USB-C 外接显示器（DP alt mode）在稳定内核上没有**，要自己编 `fairydust` 分支。HDMI
可用。

**OCI 控制台的实例指标（CPU / 内存 / 磁盘 / 网络）必须靠 agent 主动上报，不装就是空的。**
nixpkgs 没有这个包，`services/oracle-cloud-agent.nix` 从 Oracle 的 arm64 snap 里解出
静态 Go 二进制自己封装，只启用 `gomon` 一个插件。版本是手动 pin 的，升级办法见该文件
里的 `TODO revisit`。启动后要等约 50 秒才有第一次上报：这台机器是 IPv4 单栈，而 OCI
SDK 每次都先撞一遍 IPv6 元数据端点（`fd00:c1::a9fe:a9fe` 返回 404）才回退，属正常。

**别开 Custom Logs Monitoring 插件。** 它装的 `unified-monitoring-agent` 是 Oracle 打包的
Fluentd：一整套 embedded Ruby + 136 个 gem、318 MB，unit 里写着 `MemoryMax=5G`。Ubuntu
时代它在这台机器上空转吃掉几百 MB 内存（控制台侧没配日志采集，`fluentd.conf` 是 0 字节）。
`oracle-cloud-agent.nix` 的 `agent.yml` 里根本不声明它，二进制也不进 store。

**Cloud Guard Workload Protection 插件同理。** 拆开看过：snap 里的 `oci-wlp` 只是个安装
器（带着 Oracle 的 deb GPG key，二进制里就是 `apt-get -y install` / `yum -y install`），每
60 分钟醒一次去拉 `wlp-agent` 包，那个包内部跑 osqueryd。NixOS 上没 apt/dpkg/rpm，
永远装不上。

**插件的期望状态改不进 flake。** 它存在实例的 `agentConfig` 里，是 OCI 的资源属性，
只能在控制台（实例 → Oracle Cloud Agent 标签页）或 API 侧改。**重装机器后记得重新把
Custom Logs Monitoring 和 Cloud Guard Workload Protection 取消勾选**，否则那两项一直
是 Invalid，agent 每轮健康检查都为它们白跑一次重试，还会掩盖真正的故障。当前那一
页应该只剩 `Compute Instance Monitoring: Running`。

查当前期望状态（不用开控制台）：

```bash
curl -sH 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/instance/ \
  | grep -E '"name"|desiredState'
```

**合盖休眠每小时掉 2-3% 电**，是 s2idle 的已知状态（AsahiLinux/linux#262），配置层面
无解。

**新文件必须先让 jj 快照到，否则 nix 看不见**（报 `Path '...' is not tracked by
Git`）。跑一条 `jj st` 即可，原理见 `AGENTS.md`。

**btrfs 的压缩挂载选项是整个文件系统的属性，不是子卷的。** 同一个设备上所有挂载
点的 `compress-force=` 必须写成一样，否则实际生效的是最后挂上的那份。两台机器都用
`btrfsOpts` / 共享列表来保证这一点。

**改了挂载选项要重启才生效。** `nixos-rebuild switch` 不会重挂已挂载的文件系统；
压缩也只对之后写入的数据生效。

**从 `subvolid=5` 下删东西时，删不掉充当挂载点的那个目录。** 比如把顶层挂在
`/mnt/top` 后，`rm -rf /mnt/top/@/nix` 会报 `Device or resource busy`，尽管
`mountpoint /mnt/top/@/nix` 说它不是挂载点。因为 btrfs 整个 fs 共用一个 superblock、
各子卷挂载共享 dcache，这个路径和 `/` 上被 `/nix` 盖住的目录是同一个 dentry，
而内核判 EBUSY 看 dentry 不看路径。内容删得掉，目录本身删不掉——也不应该删，
没它 `/nix` 没地方挂。用 `find <dir> -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +`。

## 复查清单（TODO）

所有绕开上游 bug 的补丁、以及跟着上游版本会失效的假设，都在原地留了统一格式的
`TODO revisit:` 注释（格式约定见 `AGENTS.md`）。列出来：

```bash
rg -n --glob '!flake.lock' 'TODO revisit' /etc/nixos
```

升级 `nixpkgs` / 内核 / dms-shell 之后按这份清单走一遍，能删的就删掉，删不掉的把
`last:` 那行的日期和结论更新掉。

## 迁移历史

从 Ubuntu 26.04 经 NIXOS_LUSTRATE 原地迁移、三个 rootless 容器迁为原生服务的记录，
都在提交历史里：`jj log`。
