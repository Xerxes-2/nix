# 更新 flake.lock，并把"到底更新了什么"写进提交信息。
#
# nix 自带 `nix flake update --commit-lock-file`，但它是用 git 提交的；这个仓库
# 两台机器都用 jj，往 colocated 仓库里插 git 提交只会让 jj 事后被动 import。
# 所以这里自己读 flake.lock 的前后差异生成消息，再交给 jj commit。

usage() {
  cat <<'EOF'
用法：
  flake-update [输入名...]     更新指定输入（省略则全部），然后提交 flake.lock
  flake-update --commit-only   不更新，只为工作副本里已有的 flake.lock 改动补一个提交
  flake-update --dry-run       只打印将要生成的提交信息，不更新也不提交

提交信息里会逐条列出每个输入的 rev、日期变化，GitHub 输入还会附上 compare 链接。
EOF
}

commit_only=0
dry_run=0
inputs=()
while [ $# -gt 0 ]; do
  case "$1" in
  --commit-only) commit_only=1 ;;
  --dry-run) dry_run=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    echo "未知选项：$1" >&2
    usage >&2
    exit 2
    ;;
  *) inputs+=("$1") ;;
  esac
  shift
done

cd "$(jj workspace root)"

old=$(mktemp)
# shellcheck disable=SC2064  # 现在就要展开 $old
trap "rm -f '$old'" EXIT
jj file show -r @- flake.lock >"$old" 2>/dev/null || echo '{}' >"$old"

if [ "$commit_only" -eq 0 ] && [ "$dry_run" -eq 0 ]; then
  nix flake update ${inputs[@]+"${inputs[@]}"}
fi

# 逐节点比对，输出定长 9 字段：状态 名字 旧id 新id 旧时间 新时间 类型 owner repo
changes=$(
  jq -nr --slurpfile a "$old" --slurpfile b flake.lock '
    def id: (.rev // .narHash // "-");
    def at: (.lastModified // 0 | tostring);
    ($a[0].nodes // {}) as $an
    | ($b[0].nodes // {}) as $bn
    | ((($an | keys) + ($bn | keys)) | unique | map(select(. != "root")))[]
    | . as $k
    | ($an[$k].locked // null) as $x
    | ($bn[$k].locked // null) as $y
    | (if   $x == null then "add"
       elif $y == null then "del"
       elif ($x | id) != ($y | id) then "mod"
       else "same" end) as $st
    | select($st != "same")
    | [ $st, $k,
        (if $x then ($x | id) else "-" end),
        (if $y then ($y | id) else "-" end),
        (if $x then ($x | at) else "0" end),
        (if $y then ($y | at) else "0" end),
        (($y // $x).type // "-"),
        (($y // $x).owner // "-"),
        (($y // $x).repo  // "-")
      ] | @tsv'
)

if [ -z "$changes" ]; then
  echo "flake.lock 没有变化，无需提交。"
  exit 0
fi

short() { printf '%.7s' "$1"; }
day() {
  if [ "$1" = 0 ]; then echo "?"; else date -u -d "@$1" +%Y-%m-%d; fi
}

names=""
count=0
body=""
while IFS=$'\t' read -r st name oldid newid oldat newat type owner repo; do
  count=$((count + 1))
  names="${names:+$names, }$name"
  case "$st" in
  add) line=$(printf '%-22s 新增 %s  (%s)' "$name" "$(short "$newid")" "$(day "$newat")") ;;
  del) line=$(printf '%-22s 移除 %s' "$name" "$(short "$oldid")") ;;
  *) line=$(printf '%-22s %s → %s  %s → %s' \
    "$name" "$(short "$oldid")" "$(short "$newid")" "$(day "$oldat")" "$(day "$newat")") ;;
  esac
  body="$body$line"$'\n'
  # GitHub 输入附上 compare 链接，点开就能看这次带进来什么
  if [ "$st" = mod ] && [ "$type" = github ] && [ "$owner" != "-" ]; then
    body="$body    https://github.com/$owner/$repo/compare/$(short "$oldid")...$(short "$newid")"$'\n'
  fi
done <<<"$changes"

if [ "$count" -eq 1 ]; then
  subject="flake: 更新 ${names}"
else
  subject="flake: 更新 $count 个输入"
fi

message="$subject"$'\n\n'"$body"

if [ "$dry_run" -eq 1 ]; then
  printf '%s' "$message"
  exit 0
fi

jj commit flake.lock -m "$message"

echo
echo "已提交："
printf '%s' "$message" | sed 's/^/    /'
echo
echo "提醒：asahi 的内核来自 nixos-apple-silicon，上游没有 binary cache，"
echo "      nixpkgs 或该输入一动就要本地重编内核。先 build 再 switch："
echo "      nix build --no-link .#nixosConfigurations.asahi.config.system.build.toplevel"
