# OCI VM 原地迁移 NixOS 计划（NIXOS_LUSTRATE）

> **状态：✅ 已完成（2026-08-21）**。首次尝试因 systemd stage-1 不支持 lustrate 失败，
> 从启动卷备份恢复为新实例后修复（`boot.initrd.systemd.enable = false` +
> `efiInstallAsRemovable`），二次切换成功。apt 用户包已迁移，bees/mosh 已启用。
> 本文档与 `scripts/nixos-cutover.sh` 保留作历史参考。

> 决策：LUSTRATE 原地迁移 / quadlet-nix 管容器 / nixos-unstable / NixOS 自带 Nix
>
> 执行：Phase 0 剩余手工步骤 + Phase 3 已封装为交互式向导 `scripts/nixos-cutover.sh`，
> 在本地终端（非 ssh 断线风险环境可接受，建议 zellij/tmux 里）跑 `bash scripts/nixos-cutover.sh`。

## 0. 现状盘点

| 项目 | 现状 | 迁移后 |
|---|---|---|
| 硬件 | OCI A1.Flex aarch64, 4C/24G, 单盘 ~150G, UEFI | 不变 |
| OS | Ubuntu 26.04 | NixOS (unstable) |
| 磁盘 | sda1 btrfs（`@ @home @log @cache @tmp @containers`），sda15 ESP 98M，sda16 /boot ext4 891M | 分区/子卷布局完全不动 |
| Nix | Determinate Nix 3.21.9, /nix 33G | NixOS 自带 Nix，store 原样复用 |
| 用户 | ubuntu uid=1001, fish, linger, subuid `165536:65536` | 全部保持（subuid 必须钉死） |
| 容器 | rootless quadlet: dufs / sillytavern / wakapi | quadlet-nix 声明式，数据目录不动 |
| 系统服务 | cloudflared tunnel（token 内嵌 unit）、ssh、chrony、zram | 保留（cloudflared token 改为 root-only 文件） |
| 丢弃 | snapd 全家桶、oracle-cloud-agent、beesd、snapper 相关、unattended-upgrades、dc-bot（二进制已丢失） | 迁移后自然消失 |

## 1. 风险评估

| 风险 | 等级 | 缓解 |
|---|---|---|
| 首次重启起不来（initrd 缺盘驱动 / grub 装坏） | **高** | ① 迁移前打**启动卷全量备份**（OCI 控制台，可整机回滚）② 提前开通并**实测 OCI 串口控制台**（`console=ttyAMA0` 保留在内核参数里）③ NixOS 配置里给 root 设密码以便串口登录 |
| initrd 找不到 root（OCI 盘走 virtio-scsi/iscsi） | 高 | `boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "virtio_net" "nvme" "usbhid" ]` |
| ESP 只有 98M，systemd-boot 放不下 aarch64 内核 | 中 | 用 **GRUB (efiSupport)**：ESP 只放 grub efi，内核放 891M 的 ext4 /boot，`configurationLimit = 4` |
| SSH host key 变化 / 断连 | 中 | `NIXOS_LUSTRATE` 白名单加 `etc/ssh`，保住主机身份；cloudflared 隧道是第二通道 |
| rootless 容器 `:U` 卷的 subuid 偏移变化 → 数据权限损坏 | 中 | NixOS 里显式 `subUidRanges = [{ startUid = 165536; count = 65536; }]`（subgid 同理），`autoSubUidGidRange = false` |
| 家目录里 Ubuntu 编译的二进制失效（cargo/go 装的工具） | 低 | `programs.nix-ld.enable = true` 兜底；nix profile 装的东西不受影响 |
| Determinate Nix 特有配置丢失 | 低 | store/profile 布局与上游一致，直接复用；只是 daemon 被 NixOS 的替换 |

回滚路径：起不来 → 串口控制台修；修不了 → 控制台恢复启动卷备份，整机回到 Ubuntu。

## 2. 阶段计划

### Phase 0 — 准备（在 Ubuntu 上，不影响运行）
1. OCI 控制台：给启动卷打**手动全量备份**。
2. 开通串口控制台连接并实测登录一次。
3. 抽出秘密并落盘为 root-only 文件（迁移后被 NixOS 引用）：
   - cloudflared tunnel token（现在明文在 unit 里）→ `/etc/secrets/cloudflared-token`
   - `~/.config/wakapi/wakapi.env`（quadlet-nix 里继续用 EnvironmentFile 指向它即可，在 @home 上，不会丢）
4. （可选但推荐）家目录 19G 做一份异地 copy（restic/rclone 到 OCI 对象存储），防极端情况。

### Phase 1 — 写 NixOS 配置（扩展 ~/nixcfg flake）
新增 `nixosConfigurations.<host>`，要点：

- **文件系统**：照抄现 fstab 的 5 个 btrfs 子卷挂载 + /boot + /boot/efi，保留 `compress-force=zstd:3,noatime,discard=async`；`/tmp` tmpfs（`boot.tmp.useTmpfs`）。`@containers` 继续挂 `/home/ubuntu/.local/share/containers`。
- **引导**：GRUB EFI（`device = "nodev"; efiSupport = true;`），ESP 挂 `/boot/efi`；内核参数保留 `console=tty1 console=ttyAMA0`。
- **initrd**：virtio 模块（见上表）。
- **网络**：`networking.useDHCP` / systemd-networkd，DHCP 拿 IP 和 MTU（OCI 会推 9000）。
- **用户**：`users.users.ubuntu`：uid 1001、fish、wheel、`linger = true`、显式 subuid/subgid range、authorized_keys 兜底写一份；`users.users.root.hashedPassword` 供串口救援。
- **服务**：
  - `services.openssh.enable`
  - `services.cloudflared`（token 从 `/etc/secrets/cloudflared-token` 读）
  - `zramSwap.enable = true`
  - 时间同步：chrony 指 OCI 内部 NTP `169.254.169.254`
- **容器**：`virtualisation.podman.enable` + **quadlet-nix**，把三个 `.container` 文件逐字段翻译（PublishPort/Volume/Network=host/AutoUpdate 全有对应项），volume 路径都在 @home 上原样复用。`podman-auto-update.timer` 对应开启。
- **兼容**：`programs.nix-ld.enable = true`；`programs.fish.enable = true`；nix 开 flakes + `trusted-users`。
- 用户级包管理（现有 `packages.default` buildEnv）不动，继续 `nix profile upgrade`。

### Phase 2 — 构建验证（仍在 Ubuntu 上，零风险）
```
nix build ~/nixcfg#nixosConfigurations.<host>.config.system.build.toplevel
```
用现有 Determinate Nix 构建即可；能建出来说明配置求值/编译全通过。33G store 里已有大量依赖，增量不大。

### Phase 3 — Lustrate 切换（唯一有风险的窗口，约 15 分钟）
1. 停业务：`systemctl --user stop dufs sillytavern wakapi`，`sudo systemctl stop cloudflared`。
2. 把 toplevel 设为 system profile：
   `sudo nix build --profile /nix/var/nix/profiles/system ~/nixcfg#...toplevel`
3. `sudo touch /etc/NIXOS`；写 `/etc/NIXOS_LUSTRATE`：
   ```
   etc/nixos
   etc/ssh
   etc/secrets
   ```
   （`/home` `/var/log` 等是独立子卷，stage-1 只搬 `@` 根子卷内容，天然不受影响；`/nix` `/boot` 默认保留。）
4. 清 `/boot` 和 ESP 里 Ubuntu 的内核/grub（先 `cp -a` 备份到 `/old-boot-backup`）。
5. 安装引导：
   `sudo NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot`
6. `sudo reboot`，同时挂着串口控制台观察启动。

### Phase 4 — 迁移后验证与清理
验证清单：
- [ ] ssh 直连 + cloudflared 隧道各服务可达（dufs:5000 / wakapi:3000 / sillytavern）
- [ ] 三个容器 `systemctl --user status`，数据完好（wakapi 数据库、sillytavern 配置）
- [ ] `nix profile list` 用户包还在，fish/工具链正常
- [ ] btrfs 挂载参数、zram、时间同步正常

清理：
- `sudo rm -rf /old-root`（旧 Ubuntu 根，含 snap 数据）
- `efibootmgr` 删掉 ubuntu 启动项
- 删除遗留 snapper/beesd 快照子卷（如有）：`btrfs subvolume list /` 检查
- 观察一周稳定后，删掉 Phase 0 的启动卷备份或留作长期基线

## 3. 注意事项备忘
- **别删 oracle-cloud-agent 之外的 OCI 依赖**：NixOS 上没有 cloud-agent，控制台的"运行命令/监控"功能会失效，属预期；实例本身运行不受影响。
- Determinate Nix 的 `/etc/nix/nix.conf`、receipt 文件会随 lustrate 进 /old-root，NixOS 用自己的 nix.conf，无需迁移。
- 迁移完成后建议把 cloudflared token 之类逐步换成 sops-nix/agenix 管理。
