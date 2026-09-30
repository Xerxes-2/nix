# 跨机器共享的 CLI 工具集（Home Manager 模块，Linux/macOS 通用）。
# 各 host 的 home.nix 导入此模块，平台特有工具在各自 host 里追加。
{ pkgs, lib, ... }:
let
  # herdr 编译时把 vendor 的 libghostty-vt 用 zig 打成静态库，默认把 zig 的
  # compiler_rt/ubsan_rt 一并塞进 .a；binutils 2.46 的 ld.bfd 处理不了其中
  # .debug_loc 的重定位，链接报 `undefined reference to 'no symbol'`。
  # 照搬上游修复：Linux 上不打包这两个运行时（由系统工具链提供）。
  #   https://github.com/NixOS/nixpkgs/commit/277383a8335767cb1a59bf5ef2cc511b955f0a6b
  #
  # TODO revisit: 每次 flake 更新 nixpkgs 后
  #   check: grep -q bundle_compiler_rt "$(nix eval --raw \
  #            .#nixosConfigurations.oci.pkgs.herdr.meta.position | cut -d: -f1)"
  #   then:  命中说明上游修复已进频道，删掉这个 let 绑定，改回直接用 pkgs.herdr
  #   last:  2026-10, nixos-unstable b4fd65b 尚未包含 277383a
  herdr = pkgs.herdr.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        substituteInPlace vendor/libghostty-vt/src/build/GhosttyLibVt.zig \
          --replace-fail 'lib.bundle_compiler_rt = true;' 'lib.bundle_compiler_rt = false;' \
          --replace-fail 'lib.bundle_ubsan_rt = true;' 'lib.bundle_ubsan_rt = false;'
      '';
  });
in
{
  # 登录 shell。真正把 fish 设为登录 shell 的是各系统层的
  # `programs.fish.enable`（NixOS 上还有 `users.users.<u>.shell`；darwin 上
  # nix-darwin 的同名选项负责写 /etc/shells 和 vendor 补全）。
  #
  # 这里开的是 HM 模块，管 ~/.config/fish/config.fish，让 HM 装的包和
  # home.sessionVariables 在 fish 里也生效。
  programs.fish.enable = true;

  # 有几样自己交互时基本不碰，但编码 agent 会顺手就用（一没有就退化成
  # 手写一堆 shell 或者干脆放弃）：python3 / jq / yq-go 处理数据，file、dig、
  # socat 排查，nvd / nix-diff / nurl 专门伺候这个仓库的日常。
  home.packages = with pkgs; [
    bat
    btop
    claude-code
    codex
    curl
    difftastic
    dnsutils # dig / nslookup / nsupdate
    eza
    fastfetch
    fd
    file
    gh
    git
    go
    herdr # 用上面 let 里打过补丁的版本，不是 pkgs.herdr
    htop
    jjui
    jq
    jujutsu
    lnav
    nano
    nixd
    nix-diff # 两个 drv 到底差在哪（rebuild 结果不符预期时）
    nixfmt
    nix-index
    nodejs-slim
    nurl # 加新包时自动出 fetcher + hash，省掉手抄 sha256
    nvd # rebuild 前后的包版本 diff
    osv-scanner
    pi-coding-agent
    pnpm
    powershell
    procs
    # 不含 pip/setuptools（nixpkgs 把 ensurepip 打断了），只是个能跑
    # 脚本的完整 stdlib；要临时装第三方库用 uv。
    python3
    ripgrep
    rsync
    sd
    socat
    sqlite
    steel
    steelix
    tldr
    tokei
    tombi
    tree
    unar
    unzip
    uv
    viddy
    vim
    vscode-json-languageserver
    wakatime-cli
    wget
    yazi
    yq-go
    zellij
    zip
  ];
}
