#!/usr/bin/env bash
# oci 的 btrfs 子卷重排：从 @ 里拆出 @nix 和 @varlib。
#
# 为什么要拆，见 hosts/oci/filesystems.nix 的头部注释。简单说：
#   - /nix 是全盘最大的东西且完全可从 flake 复现，不该被任何 @ 的快照拖上；
#   - /var/lib 才是服务状态的真正所在地，而 snapper 原先只快照 /home。
#
# 这个脚本只搬数据、不改配置——.nix 那边已经声明好新挂载点了。分阶段执行，
# 每阶段前打印要做什么并等你确认；除了 phase 4 需要几分钟停机，其余都是在线的。
#
# 回滚：老数据留在 @/nix 和 @/var/lib 里，直到你显式跑 --cleanup。新一代启不起来
# 就在 GRUB 里选上一代——上一代的 stage-1 不挂 @nix/@varlib，会照常用 @ 里的老副本。
# 反过来说，--cleanup 之后迁移前的 generation 就再也启不起来了（它们的 init 指向
# @/nix，而那时已经空了）。所以先验证、再清理。

set -euo pipefail

UUID="83ee59a5-0126-4580-898e-c25d90fe9ea9"
TOP="/mnt/btrfs-top" # subvolid=5（文件系统顶层）的临时挂载点
NIXCFG="/etc/nixos"

# phase 4 要停的东西：写 /var/lib 的服务，加上会往 store 里写的 nix-daemon。
# beesd 停掉是为了别在拷贝时跟我们抢 I/O、也别去 dedup 正在成形的副本。
UNITS=(
  vaultwarden.service
  wakapi.service
  sillytavern.service
  ntfy-sh.service
  beesd@root.service
  nix-daemon.service
  nix-daemon.socket
)
TIMERS=(
  restic-backups-oci.timer
  snapper-timeline.timer
  snapper-cleanup.timer
  nix-gc.timer
  nix-optimise.timer
)

# ---------- 小工具 ----------

c_hd() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
c_ok() { printf '\033[32m  ✔ %s\033[0m\n' "$*"; }
c_wn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }
c_er() {
  printf '\033[31m  ✘ %s\033[0m\n' "$*" >&2
  exit 1
}
c_do() { printf '\033[2m  $ %s\033[0m\n' "$*"; }

confirm() {
  local reply
  printf '\n\033[1m%s\033[0m [y/N] ' "$1"
  read -r reply </dev/tty
  [[ $reply == [yY] ]]
}

run() {
  c_do "$*"
  "$@"
}

need_root() { [[ $EUID -eq 0 ]] || c_er "要 root：sudo $0 $*"; }

mount_top() {
  if mountpoint -q "$TOP"; then return; fi
  mkdir -p "$TOP"
  run mount -o subvolid=5,noatime "/dev/disk/by-uuid/$UUID" "$TOP"
}

umount_top() { mountpoint -q "$TOP" && umount "$TOP" || true; }

subvol_exists() { [[ -d "$TOP/$1" ]] && btrfs subvolume show "$TOP/$1" &>/dev/null; }

# ---------- phase 1：体检 ----------

phase_preflight() {
  c_hd "phase 1 / 体检"

  [[ -e "/dev/disk/by-uuid/$UUID" ]] || c_er "找不到 UUID=$UUID，这脚本只给 oci 用"
  c_ok "根文件系统 UUID 对得上"

  grep -q '"/@nix"' "$NIXCFG/hosts/oci/filesystems.nix" ||
    c_er "$NIXCFG/hosts/oci/filesystems.nix 里没有 @nix 条目，配置还没改？"
  c_ok "filesystems.nix 已声明 /nix 与 /var/lib"

  mount_top
  local existing=()
  for sv in @nix @varlib; do
    subvol_exists "$sv" && existing+=("$sv")
  done
  if ((${#existing[@]})); then
    c_wn "已存在：${existing[*]}（phase 2 会跳过创建，phase 4 会覆盖内容）"
  else
    c_ok "@nix / @varlib 尚不存在，是干净的起点"
  fi

  # reflink 拷贝理论上不吃额外空间，但 nix-daemon 停机期间的元数据、以及
  # /var/lib 的完整副本还是要地方。留一倍 /var/lib 的余量足够，这里只是拦
  # 明显不够的情况。
  local avail_g
  avail_g=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
  ((avail_g >= 10)) || c_er "根文件系统只剩 ${avail_g}G，先腾点空间"
  c_ok "剩余空间 ${avail_g}G"

  echo
  echo "  当前布局："
  findmnt -t btrfs -o TARGET,SOURCE --noheadings | sed 's/^/    /'
}

# ---------- phase 2：建子卷 ----------

phase_create() {
  c_hd "phase 2 / 创建子卷（在线，无影响）"
  mount_top

  for sv in @nix @varlib; do
    if subvol_exists "$sv"; then
      c_wn "$sv 已存在，跳过"
    else
      run btrfs subvolume create "$TOP/$sv"
    fi
  done

  # snapper 要求每个被快照的子卷里有自己的 .snapshots 子卷。/home 那个在
  # 容器时代就手动建过了，这里补上 @varlib 的，顺手兜底 @home 的。
  for path in "$TOP/@varlib/.snapshots" "$TOP/@home/.snapshots"; do
    if [[ -d $path ]]; then
      c_wn "$(basename "$(dirname "$path")")/.snapshots 已存在，跳过"
    else
      run btrfs subvolume create "$path"
    fi
  done

  # 容器时代 SillyTavern 构建留下的 pnpm store（12K、1 个文件）。现在 SillyTavern
  # 是原生模块、依赖走 nixpkgs，这目录没任何东西读它，却在被每小时快照。
  if [[ -d $TOP/@home/.pnpm-store ]]; then
    if confirm "删掉 /home/.pnpm-store（容器时代残留，$(du -sh "$TOP/@home/.pnpm-store" | cut -f1)）？"; then
      run rm -rf "$TOP/@home/.pnpm-store"
    fi
  else
    c_ok "/home/.pnpm-store 已不存在"
  fi
}

# ---------- phase 3：构建新一代 ----------

phase_build() {
  c_hd "phase 3 / 构建新一代（在线；写进 GRUB 但不切换当前系统）"
  echo "  这一步必须在拷贝之前跑：nixos-rebuild 会往还活着的 @/nix 里写新的 store"
  echo "  路径，拷贝要发生在它之后，新一代才拿得到自己需要的东西。"

  confirm "跑 nixos-rebuild boot？" || return 0
  run nixos-rebuild boot --flake "$NIXCFG#oci"
  c_ok "新一代已就位，下次启动生效（还没重启，当前系统不受影响）"
}

# ---------- phase 4：停机拷贝 ----------

stop_units() {
  run systemctl stop "${TIMERS[@]}" || true
  run systemctl stop "${UNITS[@]}" || true
}

start_units() {
  # 只重启服务，不重启 timer——反正马上要重启整机
  run systemctl start "${UNITS[@]}" || true
}

phase_copy() {
  c_hd "phase 4 / 停机拷贝"
  echo "  会停掉：${UNITS[*]}"
  echo "  然后从子卷原始路径（不走 /nix 那层 ro bind mount）拷到新子卷："
  echo "    $TOP/@/nix      → $TOP/@nix       cp -a --reflink=always（同 fs，共享 extent，几乎不吃空间）"
  echo "    $TOP/@/var/lib  → $TOP/@varlib    rsync -aHAX --delete"
  echo
  c_wn "从现在到重启完成，对外服务不可用（通常几分钟）"
  confirm "开始？" || return 0

  mount_top
  stop_units
  trap 'c_wn "中断了，把服务拉回来"; start_units' ERR INT TERM

  # cp -a 已含 --preserve=links，store 里 nix-store --optimise 造的硬链接会保住。
  # --reflink=always 让副本与原件共享 extent：快，且在删掉老副本前不额外占空间。
  # /nix/var/nix/daemon-socket 里的 socket 拷不了，那是 nix-daemon 每次启动重建的，
  # 报错可以忽略，所以这一条不套 set -e。
  c_do "cp -a --reflink=always $TOP/@/nix/. $TOP/@nix/"
  cp -a --reflink=always "$TOP/@/nix/." "$TOP/@nix/" || c_wn "cp 有非零退出（多半是 socket），下面会核对文件数"

  c_do "rsync -aHAX --delete --exclude=/.snapshots/ $TOP/@/var/lib/ $TOP/@varlib/"
  rsync -aHAX --delete --exclude=/.snapshots/ "$TOP/@/var/lib/" "$TOP/@varlib/"

  trap - ERR INT TERM

  local a b
  a=$(find "$TOP/@/nix/store" -maxdepth 1 | wc -l)
  b=$(find "$TOP/@nix/store" -maxdepth 1 | wc -l)
  [[ $a == "$b" ]] && c_ok "store 顶层条目数一致：$a" || c_er "store 条目数不一致：老 $a / 新 $b"

  a=$(du -s --apparent-size "$TOP/@/var/lib" | cut -f1)
  b=$(du -s --apparent-size "$TOP/@varlib" | cut -f1)
  c_ok "/var/lib 表观大小：老 $a KiB / 新 $b KiB"

  c_hd "拷贝完成 → 现在重启"
  echo "  服务先不拉起来了，直接重启，省得又写出新数据："
  echo "    sudo reboot"
  echo
  echo "  起来之后跑：sudo $0 --verify"
  echo "  起不来就在 GRUB 里选上一代——老数据还在 @/nix 和 @/var/lib 里。"
}

# ---------- phase 5：验证 ----------

phase_verify() {
  c_hd "phase 5 / 验证（重启之后跑）"

  local ok=1
  for pair in "/nix:@nix" "/var/lib:@varlib" "/home:@home" "/var/log:@log"; do
    local mp=${pair%%:*} sv=${pair##*:}
    if findmnt -no OPTIONS "$mp" 2>/dev/null | grep -q "subvol=/$sv"; then
      c_ok "$mp ← $sv"
    else
      c_wn "$mp 不在 $sv 上（实际：$(findmnt -no SOURCE "$mp" 2>/dev/null || echo 未挂载)）"
      ok=0
    fi
  done

  for u in vaultwarden wakapi sillytavern ntfy-sh; do
    if systemctl is-active --quiet "$u"; then c_ok "$u 在跑"; else
      c_wn "$u 没起来：systemctl status $u"
      ok=0
    fi
  done

  if snapper -c varlib list &>/dev/null; then c_ok "snapper varlib 配置可用"; else
    c_wn "snapper varlib 还没初始化（首个 timeline 快照要等到下个整点）"
  fi

  echo
  if ((ok)); then
    c_ok "都对。确认几天没问题后跑：sudo $0 --cleanup"
  else
    c_wn "有项目没过，先别 --cleanup"
  fi
}

# ---------- phase 6：清理老副本 ----------

phase_cleanup() {
  c_hd "phase 6 / 删除 @ 里的老副本"

  findmnt -no OPTIONS /nix | grep -q 'subvol=/@nix' || c_er "/nix 还没挂在 @nix 上，现在删等于自杀"
  findmnt -no OPTIONS /var/lib | grep -q 'subvol=/@varlib' || c_er "/var/lib 还没挂在 @varlib 上"
  c_ok "新挂载点已生效"

  mount_top
  echo
  echo "  要删："
  du -sh "$TOP/@/nix" "$TOP/@/var/lib" 2>/dev/null | sed 's/^/    /' || true
  echo
  c_wn "删完之后，迁移前的 generation 就启不起来了（它们的 init 找 @/nix，那时是空的）。"
  c_wn "GRUB 里 configurationLimit=4，迁移后再 rebuild 几次它们本来也会被挤掉。"
  confirm "确定删？" || return 0

  run rm -rf "$TOP/@/nix"
  run rm -rf "$TOP/@/var/lib"
  c_ok "删完了。空间不会立刻还回来——reflink 共享的 extent 只有在最后一个引用消失后才释放"

  echo
  df -h / | sed 's/^/    /'
}

# ---------- 入口 ----------

usage() {
  cat <<EOF
用法：sudo $0 [选项]

  （无参数）   依次跑 phase 1-4：体检 → 建子卷 → 构建新一代 → 停机拷贝，每步前确认
  --verify     phase 5：重启之后检查挂载点和服务
  --cleanup    phase 6：确认无误后删掉 @ 里的老 /nix 与 /var/lib
  -h, --help   这段

分三次进场：先跑无参数那趟 → 重启 → --verify → 观察几天 → --cleanup
EOF
}

main() {
  case "${1-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --verify)
    need_root "$@"
    phase_verify
    ;;
  --cleanup)
    need_root "$@"
    trap umount_top EXIT
    phase_cleanup
    ;;
  "")
    need_root
    trap umount_top EXIT
    phase_preflight
    confirm "继续 phase 2（创建子卷）？" || exit 0
    phase_create
    confirm "继续 phase 3（构建新一代）？" || exit 0
    phase_build
    confirm "继续 phase 4（停机拷贝）？" || exit 0
    phase_copy
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
}

main "$@"
